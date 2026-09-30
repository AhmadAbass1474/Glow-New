import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../audio/child_button_voice.dart';
import '../di/injection_container.dart';
import '../theme/app_colors.dart';
import '../../features/auth/data/child_account_service.dart';
import '../../features/auth/data/datasources/auth_local_data_source.dart';
import '../../features/auth/data/models/device_child_account.dart';
import '../../features/auth/presentation/screens/child_onboarding_screen.dart';
import '../../features/auth/presentation/widgets/account_transfer_sheets.dart';
import '../../features/auth/presentation/widgets/parent_link_sheets.dart';
import '../../features/auth/presentation/widgets/parent_provision_sheets.dart';
import 'app_bottom_sheet.dart';
import 'custom_loader.dart';

/// Opens at once from the accounts already on the phone, then refreshes.
Future<void> showChildRoleSheet(BuildContext context) {
  return _openSheet(context, 0.72, (sheetContext) {
    return _RoleAccountPicker(host: context, sheetContext: sheetContext);
  });
}

Future<void> showChildSettingsSheet(
  BuildContext context, {
  required Future<void> Function() onAccountChanged,
}) async {
  final listed = await sl<ChildAccountService>().list();
  if (!context.mounted) return;
  await _openSheet(context, 0.92, (sheetContext) {
    return _SettingsSections(
      accounts: listed,
      onSwitchAccount: () {
        _openAccountSwitch(context, sheetContext, onAccountChanged);
      },
      onCreateAccount: () => _closeThenOnboard(context, [sheetContext]),
      onLinkParent: () {
        final code = _currentAccount(listed)?.childCode ?? '';
        if (code.isEmpty) return;
        showParentLinkQr(sheetContext, childCode: code);
      },
      onAddFromParent: () {
        claimParentChildAccount(
          sheetContext,
          onReady: () async {
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            await onAccountChanged();
          },
        );
      },
      onTransfer: () {
        final active = _currentAccount(listed);
        if (active == null) return;
        showAccountTransferSheet(
          sheetContext,
          account: active,
          onMoved: (stillHere) {
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            if (!context.mounted) return;
            if (stillHere) {
              onAccountChanged();
            } else {
              context.go('/role-selection');
            }
          },
        );
      },
      onLogout: () {
        _logout(context);
      },
    );
  });
}

Future<void> _openAccountSwitch(
  BuildContext host,
  BuildContext settingsSheet,
  Future<void> Function() onAccountChanged,
) async {
  final accounts = await sl<ChildAccountService>().list();
  if (!settingsSheet.mounted) return;
  await _openSheet(settingsSheet, 0.72, (sheetContext) {
    return _AccountList(
      title: 'تبديل الحساب',
      subtitle: 'حسابات هذا الجهاز',
      accounts: accounts,
      onCreate: () => _closeThenOnboard(host, [sheetContext, settingsSheet]),
      onSelected: (account) async {
        if (account.id == sl<ChildAccountService>().activeId) {
          Navigator.of(sheetContext).pop();
          return;
        }
        final opened = await _activate(sheetContext, account);
        if (!opened) return;
        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
        if (settingsSheet.mounted) Navigator.of(settingsSheet).pop();
        onAccountChanged();
      },
    );
  });
}

Future<void> _openSheet(
  BuildContext context,
  double heightFactor,
  Widget Function(BuildContext sheetContext) child,
) {
  return showAppSheet<void>(
    context: context,
    heightFactor: heightFactor,
    builder: child,
  );
}

void _closeThenOnboard(BuildContext host, List<BuildContext> sheets) {
  for (final sheet in sheets) {
    if (sheet.mounted) Navigator.of(sheet).pop();
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (host.mounted) showChildOnboardingSheet(host);
  });
}

Future<void> _logout(BuildContext context) {
  return ChildButtonVoice.press('خروج', () async {
    await sl<AuthLocalDataSource>().clearCache();
    if (context.mounted) context.go('/role-selection');
  }, single: true);
}

Future<bool> _activate(BuildContext context, DeviceChildAccount account) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const CustomLoader(),
  );
  try {
    await sl<ChildAccountService>().activate(account);
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر فتح الحساب: $error')));
    }
    return false;
  } finally {
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _SettingsSections extends StatelessWidget {
  const _SettingsSections({
    required this.accounts,
    required this.onSwitchAccount,
    required this.onCreateAccount,
    required this.onTransfer,
    required this.onLinkParent,
    required this.onAddFromParent,
    required this.onLogout,
  });

  final List<DeviceChildAccount> accounts;
  final VoidCallback onSwitchAccount;
  final VoidCallback onCreateAccount;
  final VoidCallback onTransfer;
  final VoidCallback onLinkParent;
  final VoidCallback onAddFromParent;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final active = _currentAccount(accounts);
    return _SheetBody(
      title: 'الإعدادات',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MenuTile(
            title: 'تبديل الحساب',
            subtitle: active == null
                ? 'اختر مين بيلعب من حسابات الجهاز'
                : 'غيّر اللاعب. الحالي: ${active.name}',
            onTap: onSwitchAccount,
          ),
          const SizedBox(height: 10),
          _MenuTile(
            title: 'إنشاء حساب جديد',
            subtitle: 'أضف حساب أخ أو أخت على هذا الجهاز',
            onTap: onCreateAccount,
          ),
          const SizedBox(height: 10),
          _MenuTile(
            title: 'نقل الحساب بمساعدة ولي الأمر',
            subtitle: 'انقل هذا الحساب إلى هاتف آخر برمز',
            onTap: onTransfer,
          ),
          const SizedBox(height: 10),
          _MenuTile(
            title: 'ربط ولي الأمر',
            subtitle: 'رمز يمسحه ولي الأمر من هاتفه',
            onTap: onLinkParent,
          ),
          const SizedBox(height: 10),
          _MenuTile(
            title: 'إضافة حساب من ولي الأمر',
            subtitle: 'امسح رمز حساب أنشأه ولي الأمر، من دون تسجيل جديد',
            onTap: onAddFromParent,
          ),
        ],
      ),
      footer: _BurgundyButton(label: 'تسجيل الخروج', onPressed: onLogout),
    );
  }
}

class _RoleAccountPicker extends StatefulWidget {
  const _RoleAccountPicker({required this.host, required this.sheetContext});

  final BuildContext host;
  final BuildContext sheetContext;

  @override
  State<_RoleAccountPicker> createState() => _RoleAccountPickerState();
}

class _RoleAccountPickerState extends State<_RoleAccountPicker> {
  List<DeviceChildAccount>? _accounts;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    final service = sl<ChildAccountService>();
    final local = await service.list();
    if (!mounted) return;
    if (local.isNotEmpty) setState(() => _accounts = local);
    var fresh = local;
    try {
      fresh = await service.accountsForPicker();
    } catch (_) {}
    if (!mounted || !widget.sheetContext.mounted) return;
    if (fresh.isEmpty) {
      if (!mounted || !widget.sheetContext.mounted) return;
      setState(() => _accounts = const []);
      return;
    }
    setState(() => _accounts = fresh);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _accounts;
    if (accounts == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (accounts.isEmpty) {
      return _SheetBody(
        title: 'حساب الطفل',
        subtitle: 'أنشئ حساباً هنا، أو أضف حساباً أنشأه ولي الأمر',
        body: const SizedBox.shrink(),
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: () => _closeThenOnboard(widget.host, [widget.sheetContext]),
              child: const Text('إنشاء حساب'),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () {
                claimParentChildAccount(
                  widget.sheetContext,
                  onReady: () async {
                    if (widget.sheetContext.mounted) {
                      Navigator.of(widget.sheetContext).pop();
                    }
                    if (widget.host.mounted) widget.host.go('/child-dashboard');
                  },
                );
              },
              child: const Text('إضافة حساب من ولي الأمر'),
            ),
          ],
        ),
      );
    }
    return _AccountList(
      title: 'مين اللي بيلعب؟',
      subtitle: 'حسابات هذا الجهاز',
      accounts: accounts,
      onCreate: () => _closeThenOnboard(widget.host, [widget.sheetContext]),
      onClaimParent: () {
        claimParentChildAccount(
          widget.sheetContext,
          onReady: () async {
            if (widget.sheetContext.mounted) Navigator.of(widget.sheetContext).pop();
            if (widget.host.mounted) widget.host.go('/child-dashboard');
          },
        );
      },
      onSelected: (account) async {
        final opened = await _activate(widget.sheetContext, account);
        if (opened && widget.host.mounted) widget.host.go('/child-dashboard');
      },
    );
  }
}

class _AccountList extends StatelessWidget {
  const _AccountList({
    required this.title,
    required this.subtitle,
    required this.accounts,
    required this.onCreate,
    this.onClaimParent,
    required this.onSelected,
  });

  final String title;
  final String subtitle;
  final List<DeviceChildAccount> accounts;
  final VoidCallback onCreate;
  final VoidCallback? onClaimParent;
  final Future<void> Function(DeviceChildAccount account) onSelected;

  @override
  Widget build(BuildContext context) {
    final activeId = sl<ChildAccountService>().activeId;
    return _SheetBody(
      title: title,
      subtitle: subtitle,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < accounts.length; index++) ...[
            if (index > 0) const SizedBox(height: 10),
            _AccountTile(
              account: accounts[index],
              selected: accounts[index].id == activeId,
              onTap: () => onSelected(accounts[index]),
            ),
          ],
        ],
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(onPressed: onCreate, child: const Text('حساب جديد')),
          if (onClaimParent != null) ...[
            const SizedBox(height: 10),
            FilledButton(
              onPressed: onClaimParent,
              child: const Text('إضافة حساب من ولي الأمر'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.title,
    required this.body,
    required this.footer,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHandle(),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(child: SheetScroll(child: body)),
            const SizedBox(height: 10),
            footer,
          ],
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.inputBorder,
          borderRadius: BorderRadius.circular(AppColors.border_radius),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.title, required this.onTap, this.subtitle});

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

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.selected,
    required this.onTap,
  });

  final DeviceChildAccount account;
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
                      account.name,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.onSurface,
                      ),
                    ),
                    Text(
                      '${account.age} سنوات',
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!account.linkedRemotely)
                const Icon(
                  Icons.cloud_off_rounded,
                  color: AppColors.secondary,
                  size: 20,
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

class _BurgundyButton extends StatelessWidget {
  const _BurgundyButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.burgundy,
        foregroundColor: AppColors.onError,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.border_radius),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        textStyle: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
      child: Text(label),
    );
  }
}

DeviceChildAccount? _currentAccount(List<DeviceChildAccount> accounts) {
  final id = sl<ChildAccountService>().activeId;
  for (final account in accounts) {
    if (account.id == id) return account;
  }
  if (accounts.isEmpty) return null;
  return accounts.first;
}
