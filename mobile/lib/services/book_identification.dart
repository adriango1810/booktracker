import 'dart:async';
import 'dart:ui' show Offset, Size;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/book.dart';
import '../utils/camera_input_image.dart';
import '../utils/detection_feedback.dart';
import '../utils/isbn_validation.dart';
import '../utils/text_normalization.dart';
import 'book_api.dart';

enum ScanStatus {
  idle,
  searchingIsbn,
  readingText,
  identifying,
  detected,
  failed,
  timeout,
}

typedef UrlLaunchCallback = Future<void> Function(String url);
typedef HistorySaveCallback = Future<void> Function({
  required String title,
  required String author,
  String? isbn13,
  required String goodreadsUrl,
});

class BookIdentificationService extends ChangeNotifier {
  BookIdentificationService({
    required this.apiClient,
    required this.cameraController,
    required this.locale,
    this.barcodeFrameSkip = 5,
    this.ocrIntervalMs = 1200,
    this.ocrDelayMs = 3000,
    this.scanTimeoutMs = 20000,
    this.ocrMinTextLength = 10,
    this.autoOpenGoodreads = false,
    this.onLaunchUrl,
    this.onSaveHistory,
  }) : _barcodeScanner = BarcodeScanner();

  final BookApi apiClient;
  CameraController? cameraController;
  final String locale;
  final int barcodeFrameSkip;
  final int ocrIntervalMs;
  final int ocrDelayMs;
  final int scanTimeoutMs;
  final int ocrMinTextLength;
  final UrlLaunchCallback? onLaunchUrl;
  final HistorySaveCallback? onSaveHistory;
  bool autoOpenGoodreads;

  final BarcodeScanner _barcodeScanner;
  final TextRecognizer _textRecognizer = TextRecognizer();

  ScanStatus _status = ScanStatus.idle;
  String _statusMessage = 'Buscando código ISBN...';
  bool _isProcessing = false;
  bool _isBarcodeProcessing = false;
  bool _isOcrProcessing = false;
  bool _scanPaused = false;
  bool _ocrEnabled = false;
  bool _torchOn = false;
  bool _detectionLocked = false;

  int _frameCount = 0;
  String? _lastStableIsbn;
  int _isbnStableCount = 0;

  Timer? _ocrDelayTimer;
  Timer? _ocrTimer;
  String? _lastOcrText;
  String? _ocrPreview;
  int _ocrStableCount = 0;
  Uint8List? _latestNv21;
  int _latestWidth = 0;
  int _latestHeight = 0;
  InputImageRotation _latestRotation = InputImageRotation.rotation0deg;
  int _ocrGeneration = 0;

  Timer? _scanTimeoutTimer;

  Book? _detectedBook;
  List<BookCandidate> _candidates = [];
  String? _goodreadsUrl;
  String? _fallbackSearchText;
  bool _needsConfirmation = false;

  String? _lastSuccessfulIsbn;
  String? _lastSuccessfulOcrText;
  String? _lastSuccessfulGoodreadsUrl;
  DateTime? _lastSuccessTime;

  ScanStatus get status => _status;
  String get statusMessage => _statusMessage;
  bool get isProcessing => _isProcessing;
  Book? get detectedBook => _detectedBook;
  List<BookCandidate> get candidates => _candidates;
  String? get goodreadsUrl => _goodreadsUrl;
  String? get fallbackSearchText => _fallbackSearchText;
  String? get ocrPreview => _ocrPreview;
  bool get needsConfirmation => _needsConfirmation;
  bool get torchOn => _torchOn;
  bool get ocrEnabled => _ocrEnabled;
  /// True after a stable ISBN lock (green frame + feedback).
  bool get detectionLocked =>
      _detectionLocked || _status == ScanStatus.identifying;

  void setAutoOpenGoodreads(bool value) {
    autoOpenGoodreads = value;
    notifyListeners();
  }

  void attachCameraController(CameraController controller) {
    cameraController = controller;
    notifyListeners();
  }

  void detachCamera() {
    cameraController = null;
    notifyListeners();
  }

  bool get _isActiveScanning =>
      !_scanPaused &&
      (_status == ScanStatus.searchingIsbn ||
          _status == ScanStatus.readingText);

  bool get _shouldResumeScanning =>
      _status == ScanStatus.searchingIsbn ||
      _status == ScanStatus.readingText;

  Future<void> start() async {
    final cam = cameraController;
    if (cam == null || !cam.value.isInitialized) return;

    _resetScanState();
    _status = ScanStatus.searchingIsbn;
    _statusMessage = 'Buscando código ISBN...';
    _scanPaused = false;
    _ocrEnabled = false;
    notifyListeners();

    try {
      if (!cam.value.isStreamingImages) {
        await cam.startImageStream(_processCameraImage);
      }
    } catch (e) {
      _log('startImageStream failed: $e');
      _status = ScanStatus.failed;
      _statusMessage = 'Error de cámara. Reintenta.';
      notifyListeners();
      return;
    }

    _scheduleOcrEnable();
    _startScanTimeout();
  }

  Future<void> resumeWithCamera(CameraController controller) async {
    attachCameraController(controller);
    if (!_shouldResumeScanning) {
      _scanPaused = true;
      return;
    }

    _scanPaused = false;
    try {
      if (!controller.value.isStreamingImages) {
        await controller.startImageStream(_processCameraImage);
      }
      if (_ocrEnabled) {
        _startOcrTimer();
      } else {
        _scheduleOcrEnable();
      }
      if (_scanTimeoutTimer == null || !_scanTimeoutTimer!.isActive) {
        _startScanTimeout();
      }
      if (_torchOn) {
        await controller.setFlashMode(FlashMode.torch);
      }
    } catch (e) {
      _log('resumeWithCamera failed: $e');
    }
  }

  Future<void> pauseForBackground() async {
    _scanPaused = true;
    _ocrDelayTimer?.cancel();
    _ocrTimer?.cancel();
    _scanTimeoutTimer?.cancel();
    _latestNv21 = null;
    final cam = cameraController;
    try {
      if (cam != null &&
          cam.value.isInitialized &&
          cam.value.isStreamingImages) {
        await cam.stopImageStream();
      }
    } catch (e) {
      _log('pause stopImageStream: $e');
    }
  }

  Future<void> stop() async {
    await pauseForBackground();
    if (_status != ScanStatus.detected) {
      _status = ScanStatus.idle;
    }
    notifyListeners();
  }

  Future<void> retry() async {
    await stop();
    _status = ScanStatus.idle;
    await Future.delayed(const Duration(milliseconds: 400));
    await start();
  }

  /// Clear result and scan next book without leaving the screen.
  Future<void> nextBook() async {
    await retry();
  }

  Future<void> toggleTorch() async {
    final cam = cameraController;
    if (cam == null || !cam.value.isInitialized) return;
    try {
      _torchOn = !_torchOn;
      await cam.setFlashMode(_torchOn ? FlashMode.torch : FlashMode.off);
      notifyListeners();
    } catch (e) {
      _log('torch failed: $e');
      _torchOn = false;
      notifyListeners();
    }
  }

  void _resetScanState() {
    _isProcessing = false;
    _detectedBook = null;
    _candidates = [];
    _goodreadsUrl = null;
    _fallbackSearchText = null;
    _ocrPreview = null;
    _needsConfirmation = false;
    _lastStableIsbn = null;
    _isbnStableCount = 0;
    _detectionLocked = false;
    _lastOcrText = null;
    _ocrStableCount = 0;
    _ocrGeneration++;
    _frameCount = 0;
    _latestNv21 = null;
    _ocrEnabled = false;
    _ocrDelayTimer?.cancel();
    _ocrTimer?.cancel();
  }

  void _scheduleOcrEnable() {
    _ocrDelayTimer?.cancel();
    _ocrDelayTimer = Timer(Duration(milliseconds: ocrDelayMs), () {
      if (!_isActiveScanning || _lastStableIsbn != null || _isProcessing) {
        return;
      }
      _ocrEnabled = true;
      _status = ScanStatus.readingText;
      _statusMessage = 'Sin ISBN, leyendo título...';
      notifyListeners();
      _startOcrTimer();
    });
  }

  void _processCameraImage(CameraImage image) {
    if (!_isActiveScanning || _isProcessing) return;

    _frameCount++;
    final shouldBarcode =
        _frameCount % barcodeFrameSkip == 0 && !_isBarcodeProcessing;
    // Only convert when barcode needs it or OCR is enabled and idle.
    final shouldSnapshot =
        shouldBarcode || (_ocrEnabled && !_isOcrProcessing);

    if (!shouldSnapshot) return;

    final nv21 = CameraInputImage.yuv420ToNv21(image);
    if (nv21 == null) return;

    _latestNv21 = nv21;
    _latestWidth = image.width;
    _latestHeight = image.height;
    final cam = cameraController;
    if (cam == null) return;
    _latestRotation = CameraInputImage.rotationFor(controller: cam);

    if (shouldBarcode) {
      _processBarcode(nv21, image.width, image.height, _latestRotation);
    }
  }

  Future<void> _processBarcode(
    Uint8List nv21,
    int width,
    int height,
    InputImageRotation rotation,
  ) async {
    if (_isProcessing || _isBarcodeProcessing || !_isActiveScanning) return;

    _isBarcodeProcessing = true;
    try {
      final inputImage = InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: Size(width.toDouble(), height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: width,
        ),
      );

      final barcodes = await _barcodeScanner.processImage(inputImage);
      if (barcodes.isNotEmpty) {
        _log('Barcode raw: ${barcodes.map((b) => b.rawValue).join(", ")}');
      }

      for (final barcode in barcodes) {
        final rawValue = barcode.rawValue;
        if (rawValue == null) continue;

        final isbn = _normalizeToIsbn13(rawValue);
        if (isbn != null) {
          _handleIsbnDetected(isbn);
          return;
        }
      }
    } catch (e) {
      _log('barcode error: $e');
    } finally {
      _isBarcodeProcessing = false;
    }
  }

  String? _normalizeToIsbn13(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9Xx]'), '');
    final normalized = ISBNValidator.normalizeISBN(digits);
    if (ISBNValidator.isValidISBN13(normalized)) return normalized;
    return ISBNValidator.isbn10ToISBN13(normalized);
  }

  void _handleIsbnDetected(String isbn) {
    if (_isProcessing || !_isActiveScanning) return;

    if (_lastSuccessfulIsbn == isbn &&
        _lastSuccessTime != null &&
        DateTime.now().difference(_lastSuccessTime!).inSeconds < 3) {
      return;
    }

    // ISBN wins: cancel pending OCR.
    _ocrDelayTimer?.cancel();
    _ocrTimer?.cancel();
    _ocrEnabled = false;
    _ocrGeneration++;

    if (_lastStableIsbn == isbn) {
      _isbnStableCount++;
      if (_isbnStableCount >= 2) {
        _lastOcrText = null;
        _ocrStableCount = 0;
        if (!_detectionLocked) {
          _detectionLocked = true;
          _statusMessage = 'ISBN bloqueado: $isbn';
          notifyListeners();
          DetectionFeedback.playIsbnLocked();
        }
        _processIdentifyBook(isbn: isbn);
        return;
      }
    } else {
      _lastStableIsbn = isbn;
      _isbnStableCount = 1;
    }

    _status = ScanStatus.searchingIsbn;
    _statusMessage = 'ISBN detectado: $isbn';
    notifyListeners();
  }

  /// Tap-to-focus / exposure. [normalized] is 0–1 in preview coordinates.
  Future<void> focusAt(Offset normalized) async {
    final cam = cameraController;
    if (cam == null || !cam.value.isInitialized) return;
    final x = normalized.dx.clamp(0.0, 1.0);
    final y = normalized.dy.clamp(0.0, 1.0);
    final point = Offset(x, y);
    try {
      await cam.setFocusMode(FocusMode.auto);
      await cam.setFocusPoint(point);
      await cam.setExposurePoint(point);
      _log('focusAt ($x, $y)');
    } catch (e) {
      _log('focusAt failed: $e');
    }
  }

  void _startOcrTimer() {
    _ocrTimer?.cancel();
    _ocrTimer = Timer.periodic(Duration(milliseconds: ocrIntervalMs), (_) {
      if (!_isOcrProcessing) {
        _processOcr();
      }
    });
  }

  Future<void> _processOcr() async {
    final nv21 = _latestNv21;
    if (!_ocrEnabled ||
        _isProcessing ||
        _isOcrProcessing ||
        !_isActiveScanning ||
        _lastStableIsbn != null ||
        nv21 == null) {
      return;
    }

    _isOcrProcessing = true;
    final generation = _ocrGeneration;
    final width = _latestWidth;
    final height = _latestHeight;
    final rotation = _latestRotation;

    try {
      final cropped = CameraInputImage.cropNv21Center(nv21, width, height, 0.7);
      final bytes = cropped?.bytes ?? nv21;
      final w = cropped?.width ?? width;
      final h = cropped?.height ?? height;

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(w.toDouble(), h.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: w,
        ),
      );

      final recognizedText = await _textRecognizer.processImage(inputImage);
      if (generation != _ocrGeneration || _isProcessing) return;

      final filtered = TextNormalization.extractTitleQuery(
        recognizedText.text,
        minLength: ocrMinTextLength,
      );
      if (filtered.isNotEmpty) {
        _log('OCR filtered: $filtered');
        _handleOcrText(filtered);
      }
    } catch (e) {
      _log('ocr error: $e');
    } finally {
      _isOcrProcessing = false;
    }
  }

  void _handleOcrText(String text) {
    if (_isProcessing || !_isActiveScanning || _lastStableIsbn != null) return;

    if (_lastSuccessfulOcrText == text &&
        _lastSuccessTime != null &&
        DateTime.now().difference(_lastSuccessTime!).inSeconds < 3) {
      return;
    }

    _fallbackSearchText = text;
    _ocrPreview = text;

    if (_lastOcrText != null && TextNormalization.isSimilar(text, _lastOcrText!)) {
      _ocrStableCount++;
      if (_ocrStableCount >= 2) {
        _processIdentifyBook(ocrText: text);
      }
    } else {
      _lastOcrText = text;
      _ocrStableCount = 1;
    }

    _status = ScanStatus.readingText;
    final preview = text.length > 48 ? '${text.substring(0, 48)}…' : text;
    _statusMessage = 'Leyendo: $preview';
    notifyListeners();
  }

  void _startScanTimeout() {
    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = Timer(Duration(milliseconds: scanTimeoutMs), () {
      if (_status == ScanStatus.searchingIsbn ||
          _status == ScanStatus.readingText) {
        _scanPaused = true;
        _ocrDelayTimer?.cancel();
        _ocrTimer?.cancel();
        _status = ScanStatus.timeout;
        _statusMessage = 'No se pudo identificar';
        notifyListeners();
      }
    });
  }

  Future<void> _processIdentifyBook({String? isbn, String? ocrText}) async {
    if (_isProcessing) return;

    _isProcessing = true;
    _ocrGeneration++;
    _ocrDelayTimer?.cancel();
    _ocrTimer?.cancel();
    _status = ScanStatus.identifying;
    _statusMessage = 'Buscando libro...';
    _scanTimeoutTimer?.cancel();
    notifyListeners();

    try {
      final response = await apiClient.identifyBook(
        isbn: isbn,
        ocrText: ocrText,
        locale: locale,
        device: 'android',
      );

      if (response.candidates.isNotEmpty) {
        _candidates = response.candidates.take(3).toList();
        _needsConfirmation = false;
        _status = ScanStatus.detected;
        _statusMessage = 'Selecciona el libro correcto';
        _scanPaused = true;
        notifyListeners();
      } else if (response.book != null && response.confidence >= 0.85) {
        await _processResolveGoodreads(response.book!, nested: true);
      } else if (response.book != null && response.confidence >= 0.60) {
        _detectedBook = response.book;
        _needsConfirmation = true;
        _status = ScanStatus.detected;
        _statusMessage = '¿Es este el libro?';
        _scanPaused = true;
        notifyListeners();
      } else {
        _status = ScanStatus.failed;
        _statusMessage = 'No se pudo identificar';
        _scanPaused = true;
        notifyListeners();
      }
    } catch (_) {
      _status = ScanStatus.failed;
      _statusMessage = 'Error de conexión';
      _scanPaused = true;
      notifyListeners();
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _processResolveGoodreads(
    Book book, {
    bool nested = false,
  }) async {
    if (!nested) {
      if (_isProcessing) return;
      _isProcessing = true;
    }
    _status = ScanStatus.identifying;
    _statusMessage = 'Resolviendo Goodreads...';
    notifyListeners();

    try {
      final response = await apiClient.resolveGoodreads(
        title: book.title,
        author: book.author,
        isbn13: book.isbn13,
      );

      _detectedBook = book;

      if (response.goodreadsUrl != null && response.confidence >= 0.85) {
        await _applyGoodreadsResult(
          response.goodreadsUrl!,
          book,
          response.confidence,
        );
      } else if (response.candidates.isNotEmpty) {
        _candidates = response.candidates.take(3).toList();
        _needsConfirmation = false;
        _status = ScanStatus.detected;
        _statusMessage = 'Selecciona el libro correcto';
        _scanPaused = true;
        notifyListeners();
      } else if (response.goodreadsUrl != null && response.confidence >= 0.60) {
        _goodreadsUrl = response.goodreadsUrl;
        _needsConfirmation = true;
        _status = ScanStatus.detected;
        _statusMessage = '¿Abrir este resultado?';
        _scanPaused = true;
        notifyListeners();
      } else {
        _status = ScanStatus.failed;
        _statusMessage = 'No se pudo resolver URL';
        _scanPaused = true;
        notifyListeners();
      }
    } catch (_) {
      _status = ScanStatus.failed;
      _statusMessage = 'Error de conexión';
      _scanPaused = true;
      notifyListeners();
    } finally {
      if (!nested) {
        _isProcessing = false;
      }
    }
  }

  Future<void> _applyGoodreadsResult(
    String url,
    Book book,
    double confidence,
  ) async {
    if (_lastSuccessfulGoodreadsUrl == url &&
        _lastSuccessTime != null &&
        DateTime.now().difference(_lastSuccessTime!).inSeconds < 3) {
      return;
    }

    _goodreadsUrl = url;
    _detectedBook = book;
    _status = ScanStatus.detected;
    _statusMessage = 'Libro detectado';
    _scanPaused = true;
    _scanTimeoutTimer?.cancel();

    _lastSuccessTime = DateTime.now();
    if (book.isbn13 != null) _lastSuccessfulIsbn = book.isbn13;
    if (_lastOcrText != null) _lastSuccessfulOcrText = _lastOcrText;
    _lastSuccessfulGoodreadsUrl = url;

    notifyListeners();

    await onSaveHistory?.call(
      title: book.title,
      author: book.author,
      isbn13: book.isbn13,
      goodreadsUrl: url,
    );

    if (autoOpenGoodreads && confidence >= 0.85 && onLaunchUrl != null) {
      await pauseForBackground();
      await onLaunchUrl!(url);
    }
  }

  Future<void> selectCandidate(BookCandidate candidate) async {
    if (candidate.goodreadsUrl != null) {
      await _applyGoodreadsResult(
        candidate.goodreadsUrl!,
        Book(
          title: candidate.title,
          author: candidate.author,
          isbn13: candidate.isbn13,
        ),
        candidate.confidence ?? 0.85,
      );
    } else {
      await _processResolveGoodreads(Book(
        title: candidate.title,
        author: candidate.author,
        isbn13: candidate.isbn13,
      ));
    }
  }

  Future<void> confirmBook() async {
    if (_detectedBook == null) return;

    if (_goodreadsUrl != null) {
      if (onLaunchUrl != null) {
        await onLaunchUrl!(_goodreadsUrl!);
      }
      return;
    }

    await _processResolveGoodreads(_detectedBook!);
  }

  Future<void> openGoodreadsUrl() async {
    if (_goodreadsUrl != null && onLaunchUrl != null) {
      await onLaunchUrl!(_goodreadsUrl!);
    }
  }

  String goodreadsSearchUrl() {
    final query = _detectedBook?.title ??
        _fallbackSearchText ??
        _lastOcrText ??
        'book';
    return 'https://www.goodreads.com/search?q=${Uri.encodeComponent(query)}';
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  @override
  void dispose() {
    _ocrDelayTimer?.cancel();
    _ocrTimer?.cancel();
    _scanTimeoutTimer?.cancel();
    final cam = cameraController;
    try {
      if (cam != null &&
          cam.value.isInitialized &&
          cam.value.isStreamingImages) {
        cam.stopImageStream();
      }
    } catch (_) {}
    _barcodeScanner.close();
    _textRecognizer.close();
    super.dispose();
  }
}
