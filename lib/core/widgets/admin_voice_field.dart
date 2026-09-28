import 'dart:io';

import 'package:flutter/material.dart';

import '../audio/admin_phrase_voice.dart';

/// A normal admin input with a voice button that speaks its text.
class AdminVoiceField extends StatefulWidget {
  const AdminVoiceField({
    super.key,
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.validator,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;

  @override
  State<AdminVoiceField> createState() => _AdminVoiceFieldState();
}

class _AdminVoiceFieldState extends State<AdminVoiceField> {
  bool _busy = false;
  String _spoken = '';
  File? _file;

  Future<void> _speak() async {
    final text = widget.controller.text.trim();
    if (text.isEmpty || _busy) return;
    if (_file != null && _spoken == text) {
      await AdminPhraseVoice.play(_file!);
      return;
    }
    setState(() => _busy = true);
    try {
      final file = await AdminPhraseVoice.speak(text);
      _file = file;
      _spoken = text;
      if (!mounted) return;
      setState(() => _busy = false);
      await AdminPhraseVoice.play(file);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر توليد صوت هذا الحقل. حاول مرة أخرى.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _spoken.isNotEmpty && _spoken == widget.controller.text.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: widget.controller,
            maxLines: widget.maxLines,
            keyboardType: widget.keyboardType,
            validator: widget.validator,
            decoration: InputDecoration(hintText: widget.hint),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(
          onPressed: _busy ? null : _speak,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(ready ? 'اسمع' : 'اعمل الصوت'),
        ),
      ],
    );
  }
}
