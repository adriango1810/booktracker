import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/book_identification.dart';
import '../services/api_client.dart';
import '../services/book_api.dart';
import '../services/mock_api_client.dart';
import '../services/preferences_service.dart';
import '../utils/locale_helper.dart';
import '../widgets/camera_preview_widget.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  BookIdentificationService? _identificationService;
  PreferencesService? _preferences;
  CameraDescription? _backCamera;
  bool _hasPermission = false;
  bool _isLoading = true;
  bool _isReinitializing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_backCamera == null) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _teardownCamera();
    } else if (state == AppLifecycleState.resumed) {
      _reinitializeCamera();
    }
  }

  Future<void> _teardownCamera() async {
    await _identificationService?.pauseForBackground();
    _identificationService?.detachCamera();
    final controller = _cameraController;
    _cameraController = null;
    if (mounted) setState(() {});
    try {
      await controller?.dispose();
    } catch (e) {
      debugPrint('camera dispose: $e');
    }
  }

  Future<void> _initialize() async {
    try {
      await dotenv.load(fileName: 'assets/.env');
      _preferences = await PreferencesService.create();

      final status = await Permission.camera.request();
      if (!status.isGranted) {
        setState(() {
          _errorMessage = 'Se requiere permiso de cámara';
          _isLoading = false;
        });
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _errorMessage = 'No se encontraron cámaras';
          _isLoading = false;
        });
        return;
      }

      _backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      await _setupCameraAndService(isFirstSetup: true);
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _setupCameraAndService({required bool isFirstSetup}) async {
    final camera = _backCamera;
    if (camera == null) return;

    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await controller.initialize();
    await controller.setFocusMode(FocusMode.auto);
    await WakelockPlus.enable();
    _cameraController = controller;

    final bookApi = _createBookApi();
    final defaultAutoOpen =
        dotenv.env['AUTO_OPEN_GOODREADS']?.toLowerCase() != 'false';
    final autoOpen = _preferences!.getAutoOpenGoodreads(
      defaultValue: defaultAutoOpen,
    );

    if (_identificationService == null) {
      _identificationService = BookIdentificationService(
        apiClient: bookApi,
        cameraController: controller,
        locale: LocaleHelper.deviceLocale(),
        barcodeFrameSkip:
            int.tryParse(dotenv.env['BARCODE_FRAME_SKIP'] ?? '4') ?? 4,
        ocrIntervalMs:
            int.tryParse(dotenv.env['OCR_INTERVAL_MS'] ?? '1000') ?? 1000,
        scanTimeoutMs:
            int.tryParse(dotenv.env['SCAN_TIMEOUT_MS'] ?? '20000') ?? 20000,
        ocrMinTextLength:
            int.tryParse(dotenv.env['OCR_MIN_TEXT_LENGTH'] ?? '8') ?? 8,
        autoOpenGoodreads: autoOpen,
        onLaunchUrl: _launchUrl,
      );
      _identificationService!.addListener(_onAutoOpenChanged);
    }

    if (mounted) {
      setState(() {
        _hasPermission = true;
        _isLoading = false;
        _errorMessage = null;
      });
    }

    if (isFirstSetup) {
      await _identificationService!.start();
    } else {
      await _identificationService!.resumeWithCamera(controller);
    }
  }

  Future<void> _reinitializeCamera() async {
    if (_isReinitializing || _backCamera == null) return;
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      return;
    }
    _isReinitializing = true;
    try {
      await _setupCameraAndService(isFirstSetup: false);
    } catch (e) {
      debugPrint('reinitialize camera failed: $e');
      if (mounted) {
        setState(() => _errorMessage = 'No se pudo reiniciar la cámara');
      }
    } finally {
      _isReinitializing = false;
    }
  }

  BookApi _createBookApi() {
    final useMock = dotenv.env['USE_MOCK']?.toLowerCase() == 'true';
    if (useMock) return MockApiClient();
    return ApiClient(
      baseUrl: dotenv.env['API_BASE_URL'] ?? 'http://192.168.1.100:8000',
    );
  }

  void _onAutoOpenChanged() {
    _preferences?.setAutoOpenGoodreads(
      _identificationService!.autoOpenGoodreads,
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    // Prefer launch without canLaunchUrl — on some OEMs it returns false for HTTPS.
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      debugPrint('Could not launch $url');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _identificationService?.removeListener(_onAutoOpenChanged);
    _identificationService?.dispose();
    _cameraController?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage!),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() => _errorMessage = null);
                  _reinitializeCamera();
                },
                child: const Text('Reintentar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Volver'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_hasPermission || _identificationService == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Se requiere permiso de cámara'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Volver'),
              ),
            ],
          ),
        ),
      );
    }

    return ChangeNotifierProvider.value(
      value: _identificationService!,
      child: const _ScanScreenContent(),
    );
  }
}

class _ScanScreenContent extends StatelessWidget {
  const _ScanScreenContent();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer<BookIdentificationService>(
        builder: (context, service, child) {
          final controller = service.cameraController;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (controller != null && controller.value.isInitialized)
                CameraPreviewWidget(cameraController: controller)
              else
                const ColoredBox(color: Colors.black),
              _buildOverlay(context, service),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOverlay(BuildContext context, BookIdentificationService service) {
    return Column(
      children: [
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    service.statusMessage,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
                const Text(
                  'Auto',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Switch(
                  value: service.autoOpenGoodreads,
                  onChanged: (value) => service.setAutoOpenGoodreads(value),
                  activeTrackColor: Colors.blue.shade200,
                  activeThumbColor: Colors.white,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.7,
              height: MediaQuery.of(context).size.width * 0.7,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.5),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  'Apunta al código\no al título',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildBottomActions(context, service),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActions(
    BuildContext context,
    BookIdentificationService service,
  ) {
    switch (service.status) {
      case ScanStatus.detected:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (service.detectedBook != null)
              Text(
                '${service.detectedBook!.title}\n${service.detectedBook!.author}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (service.candidates.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...service.candidates.map(
                (candidate) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    onPressed: () => service.selectCandidate(candidate),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                    child: Text(
                      '${candidate.title}\n${candidate.author}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (service.needsConfirmation)
              ElevatedButton(
                onPressed: () => service.confirmBook(),
                child: const Text('Confirmar y buscar en Goodreads'),
              ),
            if (service.goodreadsUrl != null) ...[
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => service.openGoodreadsUrl(),
                child: const Text('Abrir resultado'),
              ),
            ],
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => service.retry(),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Reintentar escaneo'),
            ),
          ],
        );

      case ScanStatus.failed:
      case ScanStatus.timeout:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: () => service.retry(),
              child: const Text('Reintentar escaneo'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () async {
                final uri = Uri.parse(service.goodreadsSearchUrl());
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
              child: const Text('Buscar en Goodreads'),
            ),
          ],
        );

      default:
        return const SizedBox.shrink();
    }
  }
}
