import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import 'parent_link_sheets.dart';

class ParentLinkedChild {
  const ParentLinkedChild({
    required this.id,
    required this.name,
    required this.age,
  });

  final String id;
  final String name;
  final int age;
}

Future<void> showParentSettingsSheet(
  BuildContext context, {
  required List<ParentLinkedChild> children,
  required String? selectedId,
  required Future<bool> Function(String code) onLink,
  required Future<void> Function() onCreateChild,
  required Future<void> Function(String childId) onSelect,
  required Future<void> Function() onLogout,
}) {
  return showAppSheet<void>(
    context: context,
    heightFactor: 0.92,
    builder: (sheetContext) {
      return _ParentSettings(
        children: children,
        selectedId: selectedId,
        onLink: () {
          showAppSheet<void>(
            context: sheetContext,
            heightFactor: 0.72,
            builder: (linkContext) {
              return _LinkChildSection(
                onSubmit: (code) async {
                  final linked = await onLink(code);
                  if (!linked) return;
                  if (linkContext.mounted) Navigator.of(linkContext).pop();
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                },
              );
            },
          );
        },
        onCreateChild: () async {
          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
          await onCreateChild();
        },
        onSwitch: () {
          showAppSheet<void>(
            context: sheetContext,
            heightFactor: 0.72,
            builder: (switchContext) {
              return _ChildrenSwitch(
                children: children,
                selectedId: selectedId,
                onSelected: (id) async {
                  if (switchContext.mounted) Navigator.of(switchContext).pop();
                  if (id == selectedId) return;
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                  await onSelect(id);
                },
              );
            },
          );
        },
        onLogout: () async {
          Navigator.of(sheetContext).pop();
          await onLogout();
        },
      );
    },
  );
}

class _ParentSettings extends StatelessWidget {
  const _ParentSettings({
    required this.children,
    required this.selectedId,
    required this.onLink,
    required this.onCreateChild,
    required this.onSwitch,
    required this.onLogout,
  });

  final List<ParentLinkedChild> children;
  final String? selectedId;
  final VoidCallback onLink;
  final VoidCallback onCreateChild;
  final VoidCallback onSwitch;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final selected = _selectedChild(children, selectedId);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        child: Column(
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.inputBorder,
                  borderRadius: BorderRadius.circular(AppColors.border_radius),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'الإعدادات',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 16),
            _ParentTile(
              title: 'تبديل حسابات أبنائي',
              subtitle: selected == null
                  ? 'اربط أبناءك ثم اختر من تعرض بياناته'
                  : 'الحالي: ${selected.name}',
              onTap: onSwitch,
            ),
            const SizedBox(height: 10),
            _ParentTile(
              title: 'ربط ابن',
              subtitle: children.isEmpty
                  ? 'امسح رمز الابن من هاتفه'
                  : 'أضف ابناً أو ابنة بمسح الرمز',
              onTap: onLink,
            ),
            const SizedBox(height: 10),
            _ParentTile(
              title: 'إنشاء حساب لطفلي',
              subtitle: 'أنشئ الحساب وأضفه من دون أن يسجّل الطفل بنفسه',
              onTap: onCreateChild,
            ),
            const Spacer(),
            FilledButton(
              onPressed: onLogout,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.burgundy,
                foregroundColor: AppColors.onError,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppColors.border_radius),
                ),
                textStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              child: const Text('تسجيل الخروج'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkChildSection extends StatefulWidget {
  const _LinkChildSection({required this.onSubmit});

  final Future<void> Function(String code) onSubmit;

  @override
  State<_LinkChildSection> createState() => _LinkChildSectionState();
}

class _LinkChildSectionState extends State<_LinkChildSection> {
  var _busy = false;

  Future<void> _scan() async {
    if (_busy) return;
    final code = await showParentLinkScanner(context);
    if (code == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.onSubmit(code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.inputBorder,
                  borderRadius: BorderRadius.circular(AppColors.border_radius),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'ربط الابن',
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'افتح رمز الربط من هاتف الابن، ثم امسحه من هنا.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _busy ? null : _scan,
              child: const Text('مسح رمز الابن'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParentTile extends StatelessWidget {
  const _ParentTile({
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.border_radius),
        side: const BorderSide(color: AppColors.inputBorder),
      ),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.onSurface,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.secondary,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: AppColors.secondary,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChildrenSwitch extends StatelessWidget {
  const _ChildrenSwitch({
    required this.children,
    required this.selectedId,
    required this.onSelected,
  });

  final List<ParentLinkedChild> children;
  final String? selectedId;
  final Future<void> Function(String id) onSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.inputBorder,
                  borderRadius: BorderRadius.circular(AppColors.border_radius),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'حسابات أبنائي',
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'اختر الابن الذي تريد عرض بياناته',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: children.isEmpty
                  ? const Center(
                      child: Text(
                        'ما في أبناء مربوطين بعد',
                        style: TextStyle(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : SheetScroll(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var index = 0; index < children.length; index++) ...[
                            if (index > 0) const SizedBox(height: 10),
                            _ChildChoice(
                              child: children[index],
                              selected: children[index].id == selectedId,
                              onTap: () => onSelected(children[index].id),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChildChoice extends StatelessWidget {
  const _ChildChoice({
    required this.child,
    required this.selected,
    required this.onTap,
  });

  final ParentLinkedChild child;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      color: selected ? AppColors.primaryContainer : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.border_radius),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.inputBorder,
        ),
      ),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      child.name,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.onSurface,
                      ),
                    ),
                    Text(
                      '${child.age} سنوات',
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: AppColors.secondary),
            ],
          ),
        ),
      ),
    );
  }
}

ParentLinkedChild? _selectedChild(
  List<ParentLinkedChild> children,
  String? selectedId,
) {
  for (final child in children) {
    if (child.id == selectedId) return child;
  }
  if (children.isEmpty) return null;
  return children.first;
}
