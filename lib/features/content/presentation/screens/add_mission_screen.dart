import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/widgets/admin_voice_field.dart';
import '../../../content/domain/entities/world_entity.dart';
import '../../../content/domain/entities/mission_entity.dart';
import '../../../content/presentation/bloc/content_bloc.dart';
import '../../../content/presentation/bloc/content_event.dart';
import '../../../content/presentation/bloc/content_state.dart';

class AddMissionScreen extends StatefulWidget {
  final WorldEntity world;
  final MissionEntity? missionToEdit;

  const AddMissionScreen({super.key, required this.world, this.missionToEdit});

  @override
  State<AddMissionScreen> createState() => _AddMissionScreenState();
}

class _AddMissionScreenState extends State<AddMissionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _badgeController = TextEditingController();
  final _starsController = TextEditingController();
  late ContentBloc _contentBloc;

  @override
  void initState() {
    super.initState();
    _contentBloc = sl<ContentBloc>();
    if (widget.missionToEdit != null) {
      _titleController.text = widget.missionToEdit!.title;
      _badgeController.text = widget.missionToEdit!.badgeName;
      _starsController.text = widget.missionToEdit!.starsReward.toString();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _badgeController.dispose();
    _starsController.dispose();
    _contentBloc.close();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final mission = MissionEntity(
        id: widget.missionToEdit?.id ?? '', // Supabase gen_random_uuid will handle this
        worldId: widget.world.id,
        title: _titleController.text.trim(),
        badgeName: _badgeController.text.trim(),
        starsReward: int.tryParse(_starsController.text.trim()) ?? 0,
        orderIndex: widget.missionToEdit?.orderIndex ?? 0,
      );
      if (widget.missionToEdit != null) {
        _contentBloc.add(ContentEvent.updateMission(mission));
      } else {
        _contentBloc.add(ContentEvent.addMission(mission));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _contentBloc,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.missionToEdit != null ? 'تعديل المهمة' : 'إضافة مهمة لـ: ${widget.world.title}'),
        ),
        body: BlocConsumer<ContentBloc, ContentState>(
          listener: (context, state) {
            state.maybeWhen(
              missionAdded: (_) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة المهمة بنجاح!')));
                context.pop(true);
              },
              missionsLoaded: (_) {
                if (widget.missionToEdit != null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث المهمة بنجاح!')));
                  context.pop(true);
                }
              },
              error: (msg) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $msg')));
              },
              orElse: () {},
            );
          },
          builder: (context, state) {
            final isLoading = state.maybeWhen(loading: () => true, orElse: () => false);

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
                      hint: 'اسم المهمة (مثال: المهمة الأولى)',
                      validator: (val) => val == null || val.isEmpty ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 16),
                    AdminVoiceField(
                      controller: _badgeController,
                      hint: 'اسم الوسم (مثال: وسام الثقة)',
                      validator: (val) => val == null || val.isEmpty ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 16),
                    AdminVoiceField(
                      controller: _starsController,
                      hint: 'عدد النجوم (مثال: 50)',
                      keyboardType: TextInputType.number,
                      validator: (val) => val == null || val.isEmpty ? 'مطلوب' : null,
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
                        child: isLoading ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(widget.missionToEdit != null ? 'تحديث المهمة' : 'حفظ المهمة'),
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
