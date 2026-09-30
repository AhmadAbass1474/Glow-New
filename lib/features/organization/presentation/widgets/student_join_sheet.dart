import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/network/network_info.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/app_qr_scanner.dart';
import '../../../auth/data/child_account_service.dart';
import '../../../auth/data/datasources/auth_local_data_source.dart';
import '../../data/organization_service.dart';

Future<void> startStudentJoin(BuildContext context) async {
  final raw = await showAppSheet<String>(
    context: context,
    heightFactor: 0.92,
    builder: (_) => const _StudentScanner(),
  );
  if (raw == null || !context.mounted) return;

  final router = GoRouter.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
  );

  try {
    if (!await sl<NetworkInfo>().isConnected) {
      throw Exception('يحتاج الطالب اتصالاً بالإنترنت عند أول دخول');
    }
    final service = OrganizationService(Supabase.instance.client);
    final preview = await service.previewInvite(raw);
    final profile = await sl<ChildAccountService>().register(
      name: preview.name,
      age: preview.age,
      avatarUrl: 'fort_frontal.glb',
    );
    if (Supabase.instance.client.auth.currentUser?.id != profile.id) {
      throw Exception('تعذر فتح حساب الطالب');
    }
    await service.claimInvite(raw);
    await sl<AuthLocalDataSource>().forgetUser();
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    router.go('/child-dashboard');
  } catch (error) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تسجيل الطالب: $error')),
      );
    }
  }
}

class _StudentScanner extends StatefulWidget {
  const _StudentScanner();

  @override
  State<_StudentScanner> createState() => _StudentScannerState();
}

class _StudentScannerState extends State<_StudentScanner> {
  final _camera = AppQrScanHandle();
  var _reading = false;

  Future<void> _upload() async {
    if (_reading) return;
    await _camera.pause();
    try {
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (!mounted) return;
      if (files.isEmpty) {
        await _camera.resume();
        return;
      }
      setState(() => _reading = true);
      var capture = await _readFile(files.first.path);
      capture ??= await _camera.analyze(await _imageFile(files.first));
      final raw = capture?.barcodes.isEmpty ?? true
          ? null
          : capture!.barcodes.first.rawValue?.trim();
      if (!mounted) return;
      if (raw == null || raw.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ما قدرت أقرأ الرمز من الصورة. نزّل الرمز من المعلم من جديد ثم ارفعه.')),
        );
        await _camera.resume();
        return;
      }
      if (!raw.startsWith(OrganizationService.studentPrefix)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('هذه الصورة ليست رمز طالب')),
        );
        await _camera.resume();
        return;
      }
      Navigator.of(context).pop(raw);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر قراءة الصورة: $error')),
      );
      await _camera.resume();
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<BarcodeCapture?> _readFile(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      return await _camera.analyze(path);
    } catch (_) {
      return null;
    }
  }

  Future<String> _imageFile(PlatformFile file) async {
    final raw = await file.readAsBytes();
    if (raw.isEmpty) {
      throw Exception('تعذر فتح الصورة');
    }
    final codec = await ui.instantiateImageCodec(raw);
    final frame = await codec.getNextFrame();
    final source = frame.image;
    var width = source.width.toDouble();
    var height = source.height.toDouble();
    const maxSide = 1600.0;
    final longest = math.max(width, height);
    if (longest > maxSide) {
      final scale = maxSide / longest;
      width = (width * scale).roundToDouble();
      height = (height * scale).roundToDouble();
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawImageRect(
      source,
      Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      Rect.fromLTWH(0, 0, width, height),
      Paint()..filterQuality = FilterQuality.none,
    );
    final image = await recorder.endRecording().toImage(width.toInt(), height.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    source.dispose();
    image.dispose();
    if (data == null) throw Exception('تعذر فتح الصورة');
    final out = File('${(await getTemporaryDirectory()).path}/glow_student_qr.png');
    await out.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return out.path;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        const SizedBox(height: 48),
        Text(
          'رمز الطالب',
          style: textTheme.titleLarge?.copyWith(
            color: AppColors.secondary,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'صوّر الرمز بالكاميرا، أو ارفع صورته من الجهاز.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _reading ? null : _upload,
              child: Text(_reading ? 'جارٍ القراءة' : 'رفع صورة الرمز'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: AppQrScanner(
            handle: _camera,
            onCode: (raw) {
              final trimmed = raw.trim();
              if (!trimmed.startsWith(OrganizationService.studentPrefix)) return false;
              Navigator.of(context).pop(trimmed);
              return true;
            },
          ),
        ),
      ],
    );
  }
}
