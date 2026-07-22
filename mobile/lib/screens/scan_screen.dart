import 'dart:ui' show PointMode;

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
import '../services/fallback_api_client.dart';
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

    // Do NOT tear down on `inactive`: Android fires it for dialogs/overlays
    // (e.g. the auto-open prompt), which killed the camera mid-scan.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
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
      // Prompt after a short delay so it does not race camera init / overlays.
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        if (mounted) _maybePromptAutoOpen();
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _maybePromptAutoOpen() async {
    final prefs = _preferences;
    if (prefs == null || !mounted) return;
    if (prefs.hasPromptedAutoOpen) return;

    final enable = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abrir automáticamente'),
        content: const Text(
          '¿Quieres abrir Goodreads automáticamente cuando se detecte un libro con alta confianza?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí'),
          ),
        ],
      ),
    );

    await prefs.setAutoOpenPrompted();
    final value = enable ?? false;
    await prefs.setAutoOpenGoodreads(value);
    _identificationService?.setAutoOpenGoodreads(value);
  }

  Future<void> _setupCameraAndService({required bool isFirstSetup}) async {
    final camera = _backCamera;
    if (camera == null) return;

    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await controller.initialize();
    await controller.setFocusMode(FocusMode.auto);
    await WakelockPlus.enable();
    _cameraController = controller;

    final bookApi = _createBookApi();
    final defaultAutoOpen =
        dotenv.env['AUTO_OPEN_GOODREADS']?.toLowerCase() == 'true';
    final autoOpen = _preferences!.getAutoOpenGoodreads(
      defaultValue: defaultAutoOpen,
    );

    if (_identificationService == null) {
      _identificationService = BookIdentificationService(
        apiClient: bookApi,
        cameraController: controller,
        locale: LocaleHelper.deviceLocale(),
        barcodeFrameSkip:
            int.tryParse(dotenv.env['BARCODE_FRAME_SKIP'] ?? '5') ?? 5,
        ocrIntervalMs:
            int.tryParse(dotenv.env['OCR_INTERVAL_MS'] ?? '1200') ?? 1200,
        ocrDelayMs: int.tryParse(dotenv.env['OCR_DELAY_MS'] ?? '3000') ?? 3000,
        scanTimeoutMs:
            int.tryParse(dotenv.env['SCAN_TIMEOUT_MS'] ?? '20000') ?? 20000,
        ocrMinTextLength:
            int.tryParse(dotenv.env['OCR_MIN_TEXT_LENGTH'] ?? '10') ?? 10,
        autoOpenGoodreads: autoOpen,
        onLaunchUrl: _launchUrl,
        onSaveHistory: _saveHistory,
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

  Future<void> _saveHistory({
    required String title,
    required String author,
    String? isbn13,
    required String goodreadsUrl,
  }) async {
    await _preferences?.addHistoryEntry(
      ScanHistoryEntry(
        title: title,
        author: author,
        isbn13: isbn13,
        goodreadsUrl: goodreadsUrl,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
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
    final mock = MockApiClient();
    if (useMock) return mock;

    final remote = ApiClient(
      baseUrl: dotenv.env['API_BASE_URL'] ?? 'http://192.168.4.68:8000',
    );
    // If backend is down, keep scanning usable via mock.
    return FallbackBookApi(primary: remote, fallback: mock);
  }

  void _onAutoOpenChanged() {
    _preferences?.setAutoOpenGoodreads(
      _identificationService!.autoOpenGoodreads,
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
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
                IconButton(
                  icon: Icon(
                    service.torchOn ? Icons.flash_on : Icons.flash_off,
                    color: Colors.white,
                  ),
                  onPressed: () => service.toggleTorch(),
                  tooltip: 'Linterna',
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    service.statusMessage,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Portrait book-cover guide: taller than wide (~2:3).
              final maxW = constraints.maxWidth * 0.78;
              final maxH = constraints.maxHeight * 0.78;
              var frameW = maxW;
              var frameH = frameW * 1.45;
              if (frameH > maxH) {
                frameH = maxH;
                frameW = frameH / 1.45;
              }
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: frameW,
                      height: frameH,
                      child: CustomPaint(
                        painter: _BookFramePainter(
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      service.status == ScanStatus.readingText
                          ? 'Encaja la portada en el marco'
                          : 'ISBN en el lomo o portada · o el título',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (service.ocrPreview != null &&
            (service.status == ScanStatus.readingText ||
                service.status == ScanStatus.searchingIsbn))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                service.ocrPreview!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
            ElevatedButton(
              onPressed: () => service.nextBook(),
              child: const Text('Siguiente libro'),
            ),
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
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => service.nextBook(),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Siguiente libro'),
            ),
          ],
        );

      default:
        return const SizedBox.shrink();
    }
  }
}

/// Corner brackets shaped like a tall book cover (portrait).
class _BookFramePainter extends CustomPainter {
  _BookFramePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final corner = size.shortestSide * 0.18;
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    final path = Path()..addRRect(r);

    // Dim hint outline (full frame, subtle).
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.25)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    // Strong corner brackets.
    final w = size.width;
    final h = size.height;
    final corners = <List<Offset>>[
      [Offset(0, corner), Offset(0, 0), Offset(corner, 0)],
      [Offset(w - corner, 0), Offset(w, 0), Offset(w, corner)],
      [Offset(w, h - corner), Offset(w, h), Offset(w - corner, h)],
      [Offset(corner, h), Offset(0, h), Offset(0, h - corner)],
    ];
    for (final c in corners) {
      canvas.drawPoints(PointMode.polygon, c, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BookFramePainter oldDelegate) =>
      oldDelegate.color != color;
}
