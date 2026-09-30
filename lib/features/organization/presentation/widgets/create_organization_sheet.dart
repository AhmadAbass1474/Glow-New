import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../data/organization_service.dart';

Future<void> showCreateOrganizationSheet(BuildContext context) {
  return showAppSheet<void>(
    context: context,
    heightFactor: 0.72,
    avoidKeyboard: true,
    builder: (sheetContext) => _CreateOrganizationForm(
      onCreated: () {
        Navigator.of(sheetContext).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنشاء حساب المنظمة')),
        );
      },
    ),
  );
}

class _CreateOrganizationForm extends StatefulWidget {
  const _CreateOrganizationForm({required this.onCreated});

  final VoidCallback onCreated;

  @override
  State<_CreateOrganizationForm> createState() => _CreateOrganizationFormState();
}

class _CreateOrganizationFormState extends State<_CreateOrganizationForm> {
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
        const SnackBar(content: Text('اكتب اسم المنظمة والبريد وكلمة مرور من ستة أحرف')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await OrganizationService(Supabase.instance.client).createOrganizationAccount(
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text.trim(),
      );
      if (!mounted) return;
      widget.onCreated();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إنشاء المنظمة: $error')),
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
              'حساب منظمة',
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'المنظمة تدخل بهذا البريد وكلمة المرور. لا تنشئ حسابها بنفسها.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              decoration: const InputDecoration(hintText: 'اسم المنظمة'),
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
              child: Text(_busy ? 'جارٍ الإنشاء' : 'إنشاء الحساب'),
            ),
          ],
        ),
      ),
    );
  }
}
