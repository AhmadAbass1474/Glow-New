import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/organization_service.dart';

class OrganizationAuthScreen extends StatefulWidget {
  const OrganizationAuthScreen({super.key});

  @override
  State<OrganizationAuthScreen> createState() => _OrganizationAuthScreenState();
}

class _OrganizationAuthScreenState extends State<OrganizationAuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text.trim();
    if (email.isEmpty || password.length < 6) {
      _message('اكتب البريد وكلمة المرور. كلمة المرور ستة أحرف على الأقل.');
      return;
    }
    setState(() => _busy = true);
    try {
      final role = await OrganizationService(Supabase.instance.client).signIn(email, password);
      if (!mounted) return;
      context.go(role == 'teacher' ? '/teacher-dashboard' : '/organization-dashboard');
    } catch (error) {
      _message('تعذر الدخول: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'دخول المنظمة',
          style: textTheme.titleLarge?.copyWith(
            color: AppColors.secondary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(10),
        children: [
          const SizedBox(height: 12),
          const Icon(Icons.apartment_rounded, size: 64, color: AppColors.secondary),
          const SizedBox(height: 16),
          Text(
            'الحساب ينشئه مدير النظام. أدخل البريد وكلمة المرور. المعلم يدخل من هنا أيضاً.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'جارٍ الدخول' : 'دخول'),
          ),
        ],
      ),
    );
  }
}
