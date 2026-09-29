import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/smart_character_viewer.dart';
import '../../../../core/audio/child_button_voice.dart';
import '../../../../core/theme/app_colors.dart' show AppColors;
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

Future<void> showChildOnboardingSheet(BuildContext context) {
  return showAppSheet<void>(
    context: context,
    heightFactor: 0.92,
    avoidKeyboard: true,
    builder: (sheetContext) {
      return ChildOnboardingScreen(
        onRegistered: () {
          Navigator.of(sheetContext).pop();
          context.go('/child-dashboard');
        },
      );
    },
  );
}

class ChildOnboardingScreen extends StatefulWidget {
  const ChildOnboardingScreen({super.key, this.onRegistered});

  /// When set, the form is shown inside a bottom sheet.
  final VoidCallback? onRegistered;

  @override
  State<ChildOnboardingScreen> createState() => _ChildOnboardingScreenState();
}

class _ChildOnboardingScreenState extends State<ChildOnboardingScreen> {
  int _selectedAge = 5;
  String _selectedAvatar = 'fort_frontal.glb';
  final TextEditingController _nameController = TextEditingController();
  var _showCharacter = false;
  var _sheetVisible = true;

  @override
  void initState() {
    super.initState();
    if (widget.onRegistered == null) {
      _showCharacter = true;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 320), () {
        if (mounted) setState(() => _showCharacter = true);
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.of(context)?.isCurrent ?? true;
    if (visible == _sheetVisible) return;
    setState(() => _sheetVisible = visible);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  final List<String> _avatars = [
    'fort_frontal.glb',
    'lort_frontal.glb',
    'mort_frontal.glb',
    'port_frontal.glb',
    'qort_frontal.glb',
  ];

  final List<int> _ages = List.generate(10, (index) => index + 3); // 3 to 12

  @override
  Widget build(BuildContext context) {
    final inSheet = widget.onRegistered != null;
    return BlocConsumer<AuthBloc, AuthState>(
      listenWhen: (previous, current) => previous != current,
      listener: (context, state) {
        state.maybeWhen(
          childRegistered: (child) {
            final registered = widget.onRegistered;
            if (registered != null) {
              registered();
            } else {
              context.go('/child-dashboard');
            }
          },
          error: (message) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(message)));
          },
          orElse: () {},
        );
      },
      builder: (context, state) {
        final isLoading = state.maybeWhen(
          loading: () => true,
          orElse: () => false,
        );
        final fields = Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ما اسمك يا بطل؟',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(hintText: 'اكتب اسمك هنا...'),
              ),
              const SizedBox(height: 24),
              Text(
                'كم عمرك؟',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 50,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _ages.length,
                  itemBuilder: (context, index) {
                    final age = _ages[index];
                    final isSelected = age == _selectedAge;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedAge = age),
                      child: Container(
                        margin: const EdgeInsets.only(left: 8),
                        width: 50,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Theme.of(context).colorScheme.tertiary
                              : Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(
                            AppColors.border_radius,
                          ),
                          border: Border.all(
                            color: isSelected
                                ? Theme.of(context).colorScheme.tertiary
                                : Colors.grey.shade300,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$age',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.white
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'اختر شخصيتك المفضلة',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              // Big 3D Viewer for the selected avatar
              Container(
                height: 250,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7), // Amber-100
                  borderRadius: BorderRadius.circular(AppColors.border_radius),
                  border: Border.all(
                    color: const Color(0xFFF59E0B),
                    width: 3,
                  ), // Amber-500
                ),
                clipBehavior: Clip.antiAlias,
                child: _showCharacter && _sheetVisible
                    ? SmartCharacterViewer(characterName: _selectedAvatar)
                    : const SizedBox.expand(),
              ),
              const SizedBox(height: 24),

              // Selection Grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _avatars.length,
                itemBuilder: (context, index) {
                  final avatar = _avatars[index];
                  final isSelected = avatar == _selectedAvatar;
                  final name = avatar.split('_').first;
                  final displayName = name[0].toUpperCase() + name.substring(1);

                  return GestureDetector(
                    onTap: () => setState(() => _selectedAvatar = avatar),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          AppColors.border_radius,
                        ),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFF59E0B)
                              : Colors.transparent,
                          width: 3,
                        ),
                        color: isSelected
                            ? const Color(0xFFFEF3C7)
                            : Theme.of(context).colorScheme.surface,
                      ),
                      child: Center(
                        child: Text(
                          displayName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? const Color(0xFFF59E0B)
                                : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          if (_nameController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('الرجاء إدخال اسمك يا بطل!'),
                              ),
                            );
                            return;
                          }
                          final name = _nameController.text.trim();
                          ChildButtonVoice.press('انطلق', () async {
                            if (!context.mounted) return;
                            context.read<AuthBloc>().add(
                              AuthEvent.registerChild(
                                name: name,
                                age: _selectedAge,
                                avatarUrl: _selectedAvatar,
                              ),
                            );
                          }, single: true);
                        },
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('انطلق!'),
                ),
              ),
            ],
          ),
        );
        if (!inSheet) {
          return Scaffold(
            appBar: AppBar(title: const Text('مغامر جديد'), centerTitle: true),
            body: SingleChildScrollView(child: fields),
          );
        }
        final textTheme = Theme.of(context).textTheme;
        return Column(
          children: [
            const SizedBox(height: 12),
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
              'مغامر جديد',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
            Expanded(child: SheetScroll(child: fields)),
          ],
        );
      },
    );
  }
}
