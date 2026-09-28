import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/widgets/admin_voice_field.dart';
import '../../../content/domain/entities/world_entity.dart';
import '../../../content/presentation/bloc/content_bloc.dart';
import '../../../content/presentation/bloc/content_event.dart';
import '../../../content/presentation/bloc/content_state.dart';

class AddWorldScreen extends StatefulWidget {
  final WorldEntity? worldToEdit;

  const AddWorldScreen({super.key, this.worldToEdit});

  @override
  State<AddWorldScreen> createState() => _AddWorldScreenState();
}

class _AddWorldScreenState extends State<AddWorldScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _imageController = TextEditingController();
  late ContentBloc _contentBloc;
  File? _imageFile;
  String _imageUrl = '';
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _contentBloc = sl<ContentBloc>();
    if (widget.worldToEdit != null) {
      _titleController.text = widget.worldToEdit!.title;
      _descController.text = widget.worldToEdit!.description;
      _imageUrl = widget.worldToEdit!.imageUrl;
      if (_imageUrl.isNotEmpty) _imageController.text = 'تم إرفاق صورة';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _imageController.dispose();
    _contentBloc.close();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    final path = (result == null || result.isEmpty) ? null : result.first.path;
    if (path == null) return;
    setState(() {
      _imageFile = File(path);
      _imageController.text = path.split(Platform.pathSeparator).last;
    });
  }

  Future<String?> _uploadImage(File file) async {
    final ext = file.path.split('.').last.toLowerCase();
    final type = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    final name = 'world_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await Supabase.instance.client.storage.from('story_characters').upload(
          name,
          file,
          fileOptions: FileOptions(contentType: type),
        );
    return Supabase.instance.client.storage
        .from('story_characters')
        .getPublicUrl(name);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_imageFile == null && _imageUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أرفق صورة العالم')),
      );
      return;
    }
    setState(() => _uploading = true);
    try {
      final imageUrl = _imageFile == null ? _imageUrl : await _uploadImage(_imageFile!);
      if (imageUrl == null || imageUrl.isEmpty) {
        throw Exception('image');
      }
      final world = WorldEntity(
        id: widget.worldToEdit?.id ?? '',
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        imageUrl: imageUrl,
      );
      if (widget.worldToEdit != null) {
        _contentBloc.add(ContentEvent.updateWorld(world));
      } else {
        _contentBloc.add(ContentEvent.addWorld(world));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر رفع الصورة. حاول مرة أخرى.')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _contentBloc,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.worldToEdit != null ? 'تعديل عالم' : 'إضافة عالم جديد'),
        ),
        body: BlocConsumer<ContentBloc, ContentState>(
          listener: (context, state) {
            state.maybeWhen(
              worldAdded: (_) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت الإضافة بنجاح!')));
                context.pop(true);
              },
              error: (msg) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $msg')));
              },
              orElse: () {},
            );
          },
          builder: (context, state) {
            final isLoading = _uploading || state.maybeWhen(loading: () => true, orElse: () => false);

            return SafeArea(
              child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                  children: [
                    AdminVoiceField(
                      controller: _titleController,
                      hint: 'اسم العالم (مثال: الغابات)',
                      validator: (val) => val == null || val.isEmpty ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 16),
                    AdminVoiceField(
                      controller: _descController,
                      hint: 'وصف العالم',
                      maxLines: 3,
                      validator: (val) => val == null || val.isEmpty ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _imageController,
                      readOnly: true,
                      onTap: _pickImage,
                      decoration: const InputDecoration(hintText: 'إرفاق صورة'),
                    ),
                      ],
                    ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: isLoading ? null : _submit,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: isLoading ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(widget.worldToEdit != null ? 'تحديث العالم' : 'حفظ العالم'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            );
          },
        ),
      ),
    );
  }
}
