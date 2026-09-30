import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../dashboard/presentation/screens/parent_reports_screen.dart';
import '../../data/organization_service.dart';

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

  Future<void> _addStudent() async {
    final created = await showAppSheet<String>(
      context: context,
      heightFactor: 0.62,
      avoidKeyboard: true,
      builder: (sheetContext) => _AddStudentSheet(
        onSubmit: (name, age) async {
          final code = await _service.createStudentInvite(name: name, age: age);
          if (sheetContext.mounted) Navigator.of(sheetContext).pop(code);
          return code;
        },
      ),
    );
    if (!mounted || created == null) return;
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
            tooltip: 'خروج',
            onPressed: _logout,
            icon: const Icon(Icons.logout, color: AppColors.burgundy),
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
                          context.push(
                            '/parent/reports',
                            extra: ParentReportArgs(
                              childId: student.id,
                              childName: student.name,
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
                  FilledButton(
                    onPressed: _addStudent,
                    child: const Text('إضافة طالب'),
                  ),
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

class _StudentQr extends StatelessWidget {
  const _StudentQr({required this.code});

  final String code;

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
              'الطالب يفتح التطبيق ويختار طالب ويمسح هذا الرمز من هاتفه.',
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
                      data: '${OrganizationService.studentPrefix}$code',
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
