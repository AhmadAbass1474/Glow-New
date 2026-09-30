import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../data/organization_service.dart';
import '../widgets/staff_settings_sheet.dart';
import 'child_overview_screen.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  final _service = OrganizationService(Supabase.instance.client);
  var _loading = true;
  String _name = '';
  List<OrgStudent> _students = const [];
  List<PendingStudentInvite> _waiting = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final name = await _service.teacherName();
      final teacherId = Supabase.instance.client.auth.currentUser?.id ?? '';
      final students = teacherId.isEmpty ? <OrgStudent>[] : await _service.studentsOf(teacherId);
      final waiting = await _service.pendingInvites();
      if (!mounted) return;
      setState(() {
        _name = name;
        _students = students;
        _waiting = waiting;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر جلب الصف: $error')),
      );
    }
  }

  void _openSettings() {
    showStaffSettingsSheet(
      context,
      settings: [
        StaffSetting(
          title: 'إضافة طالب',
          subtitle: 'اسم وعمر، ثم رمز يمسحه الطالب من هاتفه',
          onTap: (sheetContext) => _addStudent(sheetContext),
        ),
      ],
      onLogout: _logout,
    );
  }

  Future<void> _addStudent(BuildContext sheetContext) async {
    final created = await showAppSheet<String>(
      context: sheetContext,
      heightFactor: 0.62,
      avoidKeyboard: true,
      builder: (formContext) => _AddStudentSheet(
        onSubmit: (name, age) async {
          final code = await _service.createStudentInvite(name: name, age: age);
          if (formContext.mounted) Navigator.of(formContext).pop(code);
          return code;
        },
      ),
    );
    if (created == null) return;
    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
    if (!mounted) return;
    await showAppSheet<void>(
      context: context,
      heightFactor: 0.78,
      builder: (_) => _StudentQr(code: created),
    );
    await _load();
  }

  Future<void> _logout() async {
    await _service.signOut();
    if (!mounted) return;
    context.go('/role-selection');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          _name.isEmpty ? 'صفّي' : _name,
          style: textTheme.titleLarge?.copyWith(
            color: AppColors.secondary,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'الإعدادات',
            onPressed: _openSettings,
            icon: const Icon(Icons.more_vert, color: AppColors.secondary),
          ),
        ],
      ),
      body: _loading
          ? const ShimmerLoading(type: ShimmerType.list)
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(10),
                children: [
                  Text(
                    'طلابي',
                    style: textTheme.titleMedium?.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_students.isEmpty)
                    const _NoteCard(text: 'ما في طلاب دخلوا بعد')
                  else
                    for (final student in _students) ...[
                      _StudentCard(
                        title: student.name,
                        subtitle: '${student.age} سنوات · ${student.stars} نقطة',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ChildOverviewScreen(
                                childId: student.id,
                                childName: student.name,
                                subtitle: '${student.age} سنوات',
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                  if (_waiting.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'بانتظار المسح',
                      style: textTheme.titleMedium?.copyWith(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final invite in _waiting) ...[
                      _StudentCard(
                        title: invite.name,
                        subtitle: 'لم يمسح الرمز بعد',
                        onTap: () {
                          showAppSheet<void>(
                            context: context,
                            heightFactor: 0.78,
                            builder: (_) => _StudentQr(code: invite.code),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}

class _AddStudentSheet extends StatefulWidget {
  const _AddStudentSheet({required this.onSubmit});

  final Future<String> Function(String name, int age) onSubmit;

  @override
  State<_AddStudentSheet> createState() => _AddStudentSheetState();
}

class _AddStudentSheetState extends State<_AddStudentSheet> {
  final _name = TextEditingController();
  final _age = TextEditingController();
  var _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final age = int.tryParse(_age.text.trim());
    if (_name.text.trim().isEmpty || age == null || age < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب اسم الطالب وعمره')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onSubmit(_name.text.trim(), age);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إنشاء الطالب: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 48, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'طالب جديد',
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'بعد الحفظ يظهر رمز. الطالب يمسحه من هاتفه.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(hintText: 'اسم الطالب'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _age,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'العمر'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'جارٍ الإنشاء' : 'إنشاء الرمز'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudentQr extends StatefulWidget {
  const _StudentQr({required this.code});

  final String code;

  @override
  State<_StudentQr> createState() => _StudentQrState();
}

class _StudentQrState extends State<_StudentQr> {
  var _saving = false;

  Future<void> _download() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await _qrPng('${OrganizationService.studentPrefix}${widget.code}');
      if (bytes.isEmpty) {
        throw Exception('تعذر تجهيز الصورة');
      }
      final saved = await FilePicker.saveFile(
        fileName: 'student-${widget.code}.png',
        bytes: bytes,
        mimeType: 'image/png',
      );
      if (!mounted || saved == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تنزيل رمز الطالب')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تنزيل الرمز: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<Uint8List> _qrPng(String data) async {
    const qrSize = 900.0;
    const margin = 96.0;
    const side = qrSize + margin * 2;
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.H,
      gapless: true,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Color(0xFF000000),
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Color(0xFF000000),
      ),
    );
    final qr = await painter.toImage(qrSize);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, side, side),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawImage(qr, const Offset(margin, margin), Paint());
    final image = await recorder.endRecording().toImage(side.toInt(), side.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    qr.dispose();
    image.dispose();
    if (bytes == null) throw Exception('تعذر تجهيز الصورة');
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 48, 10, 10),
        child: Column(
          children: [
            Text(
              'رمز الطالب',
              style: textTheme.titleLarge?.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'امسحه من هاتف الطالب، أو نزّل الصورة وأرسلها له.',
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
                      data: '${OrganizationService.studentPrefix}${widget.code}',
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
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _download,
                child: Text(_saving ? 'جارٍ التنزيل' : 'تنزيل الرمز'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudentCard extends StatelessWidget {
  const _StudentCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.border_radius),
        side: const BorderSide(color: AppColors.inputBorder, width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppColors.border_radius),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.secondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.border_radius),
        border: Border.all(color: AppColors.inputBorder, width: 1.5),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: AppColors.secondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
