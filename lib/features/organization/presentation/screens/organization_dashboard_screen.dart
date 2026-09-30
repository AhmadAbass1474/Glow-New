import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../dashboard/presentation/screens/parent_reports_screen.dart';
import '../../data/organization_service.dart';
import '../widgets/staff_settings_sheet.dart';

class OrganizationDashboardScreen extends StatefulWidget {
  const OrganizationDashboardScreen({super.key});

  @override
  State<OrganizationDashboardScreen> createState() => _OrganizationDashboardScreenState();
}

class _OrganizationDashboardScreenState extends State<OrganizationDashboardScreen> {
  final _service = OrganizationService(Supabase.instance.client);
  var _loading = true;
  String _name = '';
  List<OrgTeacher> _teachers = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final name = await _service.organizationName();
      final teachers = await _service.teachers();
      if (!mounted) return;
      setState(() {
        _name = name;
        _teachers = teachers;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر جلب المنظمة: $error')),
      );
    }
  }

  void _openSettings() {
    showStaffSettingsSheet(
      context,
      settings: [
        StaffSetting(
          title: 'إضافة معلم',
          subtitle: 'اسم وبريد وكلمة مرور. المعلم يدخل من شاشة المنظمة',
          onTap: (sheetContext) async {
            final added = await _addTeacher(sheetContext);
            if (added != true || !sheetContext.mounted) return;
            Navigator.of(sheetContext).pop();
            await _load();
          },
        ),
      ],
      onLogout: _logout,
    );
  }

  Future<bool?> _addTeacher(BuildContext sheetContext) {
    return showAppSheet<bool>(
      context: sheetContext,
      heightFactor: 0.72,
      avoidKeyboard: true,
      builder: (formContext) => _AddTeacherSheet(
        onSubmit: (name, email, password) async {
          await _service.addTeacher(name: name, email: email, password: password);
          if (formContext.mounted) Navigator.of(formContext).pop(true);
        },
      ),
    );
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
          _name.isEmpty ? 'المنظمة' : _name,
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
                    'المعلمون',
                    style: textTheme.titleMedium?.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'كل معلم وصفّه. اضغط المعلم لترى طلابه وتقاريرهم.',
                    style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
                  ),
                  const SizedBox(height: 12),
                  if (_teachers.isEmpty)
                    const _EmptyCard(text: 'لم تُضف معلمين بعد')
                  else
                    for (final teacher in _teachers) ...[
                      _PersonCard(
                        title: teacher.name,
                        subtitle: 'معلم',
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => _TeacherClassScreen(teacher: teacher),
                            ),
                          );
                          if (mounted) await _load();
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
            ),
    );
  }
}

class _TeacherClassScreen extends StatefulWidget {
  const _TeacherClassScreen({required this.teacher});

  final OrgTeacher teacher;

  @override
  State<_TeacherClassScreen> createState() => _TeacherClassScreenState();
}

class _TeacherClassScreenState extends State<_TeacherClassScreen> {
  final _service = OrganizationService(Supabase.instance.client);
  var _loading = true;
  List<OrgStudent> _students = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _openSettings() {
    showStaffSettingsSheet(
      context,
      settings: [
        StaffSetting(
          title: 'إضافة معلم',
          subtitle: 'اسم وبريد وكلمة مرور. المعلم يدخل من شاشة المنظمة',
          onTap: (sheetContext) async {
            final added = await showAppSheet<bool>(
              context: sheetContext,
              heightFactor: 0.72,
              avoidKeyboard: true,
              builder: (formContext) => _AddTeacherSheet(
                onSubmit: (name, email, password) async {
                  await _service.addTeacher(name: name, email: email, password: password);
                  if (formContext.mounted) Navigator.of(formContext).pop(true);
                },
              ),
            );
            if (added == true && sheetContext.mounted) Navigator.of(sheetContext).pop();
          },
        ),
      ],
      onLogout: () async {
        await _service.signOut();
        if (!mounted) return;
        context.go('/role-selection');
      },
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final students = await _service.studentsOf(widget.teacher.id);
      if (!mounted) return;
      setState(() {
        _students = students;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر جلب الطلاب: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          widget.teacher.name,
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
          : ListView(
              padding: const EdgeInsets.all(10),
              children: [
                if (_students.isEmpty)
                  const _EmptyCard(text: 'هذا المعلم لم يُضف طلاباً بعد')
                else
                  for (final student in _students) ...[
                    _PersonCard(
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
              ],
            ),
    );
  }
}

class _AddTeacherSheet extends StatefulWidget {
  const _AddTeacherSheet({required this.onSubmit});

  final Future<void> Function(String name, String email, String password) onSubmit;

  @override
  State<_AddTeacherSheet> createState() => _AddTeacherSheetState();
}

class _AddTeacherSheetState extends State<_AddTeacherSheet> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        _password.text.trim().length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب اسم المعلم والبريد وكلمة مرور من ستة أحرف')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onSubmit(
        _name.text.trim(),
        _email.text.trim(),
        _password.text.trim(),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إضافة المعلم: $error')),
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
              'معلم جديد',
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(hintText: 'اسم المعلم'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(hintText: 'البريد الإلكتروني'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(hintText: 'كلمة المرور'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'جارٍ الإضافة' : 'إضافة المعلم'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({
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

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

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
