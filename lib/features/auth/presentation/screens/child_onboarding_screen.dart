import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/smart_character_viewer.dart';
import '../../../../core/audio/child_button_voice.dart';
import '../../../../core/theme/app_colors.dart' show AppColors;
import '../bloc/auth_bloc.dart';
import '../bloc/auth_event.dart';
import '../bloc/auth_state.dart';

class ChildOnboardingScreen extends StatefulWidget {
  const ChildOnboardingScreen({super.key});

  @override
  State<ChildOnboardingScreen> createState() => _ChildOnboardingScreenState();
}

class _ChildOnboardingScreenState extends State<ChildOnboardingScreen> {
  int _selectedAge = 5;
  String _selectedAvatar = 'fort_frontal.glb';
  final TextEditingController _nameController = TextEditingController();

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('مغامر جديد'),
        centerTitle: true,
      ),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          state.maybeWhen(
            childRegistered: (child) {
              context.go('/child-dashboard');
            },
            error: (message) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(message)),
              );
            },
            orElse: () {},
          );
        },
        builder: (context, state) {
          final isLoading = state.maybeWhen(
            loading: () => true,
            orElse: () => false,
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(
              'ما اسمك يا بطل؟',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: 'اكتب اسمك هنا...',
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'كم عمرك؟',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
                        color: isSelected ? Theme.of(context).colorScheme.tertiary : Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(AppColors.border_radius),
                        border: Border.all(
                          color: isSelected ? Theme.of(context).colorScheme.tertiary : Colors.grey.shade300,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$age',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface,
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
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            // Big 3D Viewer for the selected avatar
            Container(
              height: 250,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7), // Amber-100
                borderRadius: BorderRadius.circular(AppColors.border_radius),
                border: Border.all(color: const Color(0xFFF59E0B), width: 3), // Amber-500
              ),
              clipBehavior: Clip.antiAlias,
              child: SmartCharacterViewer(
                characterName: _selectedAvatar,
              ),
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
                      borderRadius: BorderRadius.circular(AppColors.border_radius),
                      border: Border.all(
                        color: isSelected ? const Color(0xFFF59E0B) : Colors.transparent,
                        width: 3,
                      ),
                      color: isSelected ? const Color(0xFFFEF3C7) : Theme.of(context).colorScheme.surface,
                    ),
                    child: Center(
                      child: Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? const Color(0xFFF59E0B) : Colors.grey,
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
                onPressed: isLoading ? null : () {
                  if (_nameController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('الرجاء إدخال اسمك يا بطل!')),
                    );
                    return;
                  }
                  final name = _nameController.text.trim();
                  ChildButtonVoice.press('انطلق', () async {
                    if (!context.mounted) return;
                    context.read<AuthBloc>().add(AuthEvent.registerChild(
                      name: name,
                      age: _selectedAge,
                      avatarUrl: _selectedAvatar,
                    ));
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
    },
  ),
);
  }
}

