import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_colors.dart';

/// Camera preview for a QR sheet. The camera starts after the sheet is open,
/// using the selector that works on real Android phones.
class AppQrScanner extends StatefulWidget {
  const AppQrScanner({super.key, required this.onCode});

  /// Return true when [raw] was accepted and the sheet should close.
  final bool Function(String raw) onCode;

  @override
  State<AppQrScanner> createState() => _AppQrScannerState();
}

class _AppQrScannerState extends State<AppQrScanner> {
  MobileScannerController? _camera;
  var _handled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 450), () {
        if (!mounted || _handled) return;
        _openCamera();
      });
    });
  }

  void _openCamera() {
    final previous = _camera;
    setState(() {
      _camera = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        detectionTimeoutMs: 400,
        facing: CameraFacing.back,
        formats: const [BarcodeFormat.qrCode],
        returnImage: false,
        useNewCameraSelector: true,
      );
    });
    if (previous != null) unawaited(previous.dispose());
  }

  @override
  void dispose() {
    final camera = _camera;
    if (camera != null) unawaited(camera.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || !mounted) return;
    final raw = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;
    if (!widget.onCode(raw)) return;
    _handled = true;
    final camera = _camera;
    if (camera != null) unawaited(camera.stop());
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight) * 0.72;
        final window = Rect.fromCenter(
          center: Offset(constraints.maxWidth / 2, constraints.maxHeight / 2),
          width: side,
          height: side,
        );
        final camera = _camera;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (camera == null)
              const ColoredBox(color: AppColors.secondary)
            else
              MobileScanner(
                controller: camera,
                onDetect: _onDetect,
                errorBuilder: (context, error, child) {
                  return _CameraMessage(
                    message: _cameraMessage(error),
                    onRetry: _handled ? null : _openCamera,
                  );
                },
              ),
            IgnorePointer(
              child: CustomPaint(
                painter: _QrFramePainter(window),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        );
      },
    );
  }
}

String _cameraMessage(MobileScannerException error) {
  switch (error.errorCode) {
    case MobileScannerErrorCode.permissionDenied:
      return 'اسمح للكاميرا حتى يُمسح الرمز. إذا رفضت الإذن من قبل، فعّله من إعدادات التطبيق ثم أعد المحاولة.';
    case MobileScannerErrorCode.unsupported:
      return 'هذا الجهاز لا يوفّر كاميرا للمسح.';
    case MobileScannerErrorCode.genericError:
    case MobileScannerErrorCode.controllerAlreadyInitialized:
    case MobileScannerErrorCode.controllerDisposed:
    case MobileScannerErrorCode.controllerUninitialized:
      final detail = error.errorDetails?.message;
      if (detail != null && detail.isNotEmpty) {
        return 'تعذر فتح الكاميرا. $detail';
      }
      return 'تعذر فتح الكاميرا. أعد المحاولة، وتأكد أن إذن الكاميرا مفعّل.';
  }
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ColoredBox(
      color: AppColors.secondary,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.onSecondary,
                  fontWeight: FontWeight.w700,
                  height: 1.5,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QrFramePainter extends CustomPainter {
  const _QrFramePainter(this.window);

  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final shade = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(
        RRect.fromRectAndRadius(window, Radius.circular(AppColors.border_radius)),
      )
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(shade, Paint()..color = const Color(0x88001946));
    canvas.drawRRect(
      RRect.fromRectAndRadius(window, Radius.circular(AppColors.border_radius)),
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _QrFramePainter oldDelegate) => oldDelegate.window != window;
}
