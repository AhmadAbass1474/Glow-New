import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';

/// The QR is the child's existing link code. No extra row and no camera
/// until the parent opens the scanner.
class ParentLinkCode {
  static const prefix = 'glk:';

  static String payload(String childCode) => '$prefix$childCode';

  static String? parse(String raw) {
    if (!raw.startsWith(prefix)) return null;
    final code = raw.substring(prefix.length).trim();
    if (!RegExp(r'^CH-\d{4}$').hasMatch(code)) return null;
    return code;
  }
}

Future<void> showParentLinkQr(BuildContext context, {required String childCode}) {
  return showAppSheet<void>(
    context: context,
    heightFactor: 0.72,
    builder: (_) => _ParentLinkQr(childCode: childCode),
  );
}

Future<String?> showParentLinkScanner(BuildContext context) {
  return showAppSheet<String>(
    context: context,
    heightFactor: 0.92,
    builder: (_) => const _ParentLinkScanner(),
  );
}

class _ParentLinkQr extends StatelessWidget {
  const _ParentLinkQr({required this.childCode});

  final String childCode;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.inputBorder,
                borderRadius: BorderRadius.circular(AppColors.border_radius),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'ربط ولي الأمر',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'ولي الأمر يمسح هذا الرمز من لوحته.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final side = math.min(constraints.maxWidth, constraints.maxHeight);
                  return Center(
                    child: QrImageView(
                      data: ParentLinkCode.payload(childCode),
                      size: side,
                      backgroundColor: AppColors.surface,
                      errorCorrectionLevel: QrErrorCorrectLevel.L,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: AppColors.secondary,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: AppColors.secondary,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'الجهازان متصلان، والرمز خاص بهذا الابن.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParentLinkScanner extends StatefulWidget {
  const _ParentLinkScanner();

  @override
  State<_ParentLinkScanner> createState() => _ParentLinkScannerState();
}

class _ParentLinkScannerState extends State<_ParentLinkScanner> {
  MobileScannerController? _camera;
  var _handled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 280), () {
        if (!mounted || _handled) return;
        setState(() {
          _camera = MobileScannerController(
            detectionSpeed: DetectionSpeed.normal,
            detectionTimeoutMs: 400,
            facing: CameraFacing.back,
            formats: const [BarcodeFormat.qrCode],
            returnImage: false,
          );
        });
      });
    });
  }

  @override
  void dispose() {
    final camera = _camera;
    if (camera != null) unawaited(camera.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    final code = raw == null ? null : ParentLinkCode.parse(raw);
    if (code == null) return;
    _handled = true;
    final camera = _camera;
    if (camera != null) unawaited(camera.stop());
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.inputBorder,
                borderRadius: BorderRadius.circular(AppColors.border_radius),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'مسح رمز الابن',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppColors.border_radius),
                child: LayoutBuilder(
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
                        if (camera != null)
                          MobileScanner(
                            controller: camera,
                            onDetect: _onDetect,
                            scanWindow: window,
                          ),
                        IgnorePointer(
                          child: CustomPaint(
                            painter: _LinkFramePainter(window),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'ضع رمز الابن داخل الإطار الأصفر',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkFramePainter extends CustomPainter {
  const _LinkFramePainter(this.window);

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
  bool shouldRepaint(covariant _LinkFramePainter oldDelegate) => oldDelegate.window != window;
}
