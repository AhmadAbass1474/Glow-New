import 'package:Glow/core/di/injection_container.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../auth/presentation/widgets/parent_link_sheets.dart';
import '../../../auth/presentation/widgets/parent_settings_sheet.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../auth/data/datasources/auth_local_data_source.dart';
import '../../../content/domain/repositories/content_repository.dart';
import '../../../content/domain/entities/child_progress_entity.dart';
import 'parent_reports_screen.dart';

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _LinkedChild {
  const _LinkedChild({
    required this.id,
    required this.name,
    required this.age,
    required this.code,
  });

  final String id;
  final String name;
  final int age;
  final String code;
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  bool _isLoading = true;
  List<_LinkedChild> _children = [];
  String? _childId;
  String? _childName;

  int _totalStars = 0;
  int _totalMissions = 0;
  int _totalBadges = 0;

  List<ChildProgressEntity> _recentProgress = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData({String? preferCode}) async {
    setState(() => _isLoading = true);

    try {
      final parentId = Supabase.instance.client.auth.currentUser?.id;

      if (parentId != null) {
        final childrenData = await Supabase.instance.client
            .from('children_profiles')
            .select()
            .eq('parent_id', parentId);

        final linked = <_LinkedChild>[
          for (final row in childrenData)
            _LinkedChild(
              id: row['id'] as String,
              name: (row['name'] as String?) ?? '',
              age: (row['age'] as num?)?.toInt() ?? 0,
              code: (row['child_code'] as String?) ?? '',
            ),
        ]..sort((a, b) => a.name.compareTo(b.name));

        final savedId = await sl<AuthLocalDataSource>().getParentSelectedChild();
        final wantedCode = preferCode?.trim();
        _LinkedChild? selected;
        for (final child in linked) {
          if (wantedCode != null &&
              wantedCode.isNotEmpty &&
              child.code == wantedCode) {
            selected = child;
            break;
          }
        }
        if (selected == null && savedId != null) {
          for (final child in linked) {
            if (child.id == savedId) {
              selected = child;
              break;
            }
          }
        }
        if (selected == null && linked.isNotEmpty) selected = linked.first;

        _children = linked;
        _childId = selected?.id;
        _childName = selected?.name;
        if (selected != null) {
          await sl<AuthLocalDataSource>().cacheParentSelectedChild(selected.id);
        }

        if (mounted) {
          setState(() {
            _totalStars = 0;
            _totalBadges = 0;
            _totalMissions = 0;
            _recentProgress = [];
          });
        }
      }

      if (_childId != null) {
        final result = await sl<ContentRepository>().getCompletedMissions(
          _childId!,
        );

        result.fold(
          (failure) {
            debugPrint(
              "Error fetching parent dashboard data: ${failure.message}",
            );
          },
          (progressList) {
            int stars = 0;
            int badges = 0;
            for (var p in progressList) {
              stars += (p.starsReward ?? 0).toInt();
              if (p.badgeName != null && p.badgeName!.isNotEmpty) {
                badges++;
              }
            }

            // Sort by recent
            progressList.sort((a, b) => b.completedAt.compareTo(a.completedAt));

            setState(() {
              // Only override stats if progressList actually has data
              if (progressList.isNotEmpty) {
                _totalStars = stars;
                _totalBadges = badges;
              }
              _totalMissions = progressList.length;
              _recentProgress = progressList;
            });
          },
        );
      }
    } catch (e) {
      debugPrint("Parent Dashboard Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('خطأ في جلب البيانات: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<bool> _linkChild(String scanned) async {
    final code = scanned.trim();
    if (code.isEmpty) return false;

    setState(() => _isLoading = true);

    try {
      final parentId = Supabase.instance.client.auth.currentUser?.id;
      if (parentId == null) {
        if (mounted) setState(() => _isLoading = false);
        return false;
      }
      await Supabase.instance.client.rpc('link_parent_to_child', params: {
        'p_parent_id': parentId,
        'p_child_code': code,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم ربط حساب طفلك بنجاح!')),
        );
      }
      await _fetchData(preferCode: code);
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر الربط. تأكد أن الرمز ما زال ظاهرًا.')),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'لوحة تحكم ولي الأمر',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppColors.secondary,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Material(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppColors.border_radius),
                side: const BorderSide(color: AppColors.inputBorder, width: 1.5),
              ),
              child: InkWell(
                onTap: () {
                  context.push(
                    '/parent/reports',
                    extra: ParentReportArgs(childId: _childId, childName: _childName),
                  );
                },
                borderRadius: BorderRadius.circular(AppColors.border_radius),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    'تقارير',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'الإعدادات',
            onPressed: () {
              showParentSettingsSheet(
                context,
                children: [
                  for (final child in _children)
                    ParentLinkedChild(
                      id: child.id,
                      name: child.name,
                      age: child.age,
                    ),
                ],
                selectedId: _childId,
                onLink: (code) => _linkChild(code),
                onSelect: (id) async {
                  await sl<AuthLocalDataSource>().cacheParentSelectedChild(id);
                  if (!mounted) return;
                  await _fetchData();
                },
                onLogout: () async {
                  await sl<AuthLocalDataSource>().clearCache();
                  if (context.mounted) context.go('/role-selection');
                },
              );
            },
            icon: const Icon(Icons.more_vert, color: AppColors.secondary),
          ),
        ],
      ),
      body: RefreshIndicator(
          onRefresh: _fetchData,
          color: AppColors.primary,
          child: _isLoading
              ? const ShimmerLoading(type: ShimmerType.list)
              : SafeArea(
                  child: _childId == null
                      ? CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [_buildLinkChildView()],
                                ),
                              ),
                            ),
                          ],
                        )
                      : SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _childName ?? '',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.secondary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildInsightsBanner(),
                              const SizedBox(height: 24),
                              _buildMetricsGrid(),
                              const SizedBox(height: 32),
                              Text(
                                'أحدث الإنجازات',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.secondary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildRecentAchievements(),
                            ],
                          ),
                        ),
                ),
      ),
    );
  }

  Future<void> _scanAndLink() async {
    final code = await showParentLinkScanner(context);
    if (code == null || !mounted) return;
    await _linkChild(code);
  }

  Widget _buildLinkChildView() {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.border_radius),
        border: Border.all(color: AppColors.inputBorder, width: 1.5),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.qr_code_scanner,
            size: 64,
            color: AppColors.secondary,
          ),
          const SizedBox(height: 16),
          Text(
            'لم تربط حساب ابنك بعد',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.secondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'من هاتف الابن افتح ربط ولي الأمر، ثم امسح الرمز من هنا.',
            style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isLoading ? null : _scanAndLink,
              child: const Text('مسح رمز الابن'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsBanner() {
    // Dynamic insight message based on engagement
    String message = 'لم يبدأ البطل أي مهمات بعد. شجعه على الانطلاق!';
    IconData icon = Icons.wb_incandescent_rounded;
    Color color = AppColors.primary;

    if (_totalMissions > 10) {
      message = 'رائع جداً! بطلنا يتقدم بشكل ممتاز ومنتظم في إنجاز التحديات.';
      icon = Icons.emoji_events_rounded;
      color = AppColors.tertiary;
    } else if (_totalMissions > 0) {
      message = 'بداية موفقة! بطلنا يكتسب مهارات جديدة مع كل مهمة.';
      icon = Icons.star_rounded;
      color = AppColors.secondary;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.border_radius),
        border: Border.all(color: AppColors.inputBorder, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'رسالة تشجيعية',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            title: 'المهمات',
            value: _totalMissions.toString(),
            icon: Icons.task_alt_rounded,
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            title: 'النقاط',
            value: _totalStars.toString(),
            icon: Icons.star_rounded,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            title: 'الأوسمة',
            value: _totalBadges.toString(),
            icon: Icons.workspace_premium_rounded,
            color: AppColors.tertiary,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.border_radius),
        border: Border.all(color: AppColors.inputBorder, width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.secondary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentAchievements() {
    if (_recentProgress.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              const Icon(Icons.history_rounded, size: 60, color: AppColors.inputBorder),
              const SizedBox(height: 16),
              Text(
                'لا توجد إنجازات بعد',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _recentProgress.length > 5
          ? 5
          : _recentProgress.length, // Show up to 5 recent
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final progress = _recentProgress[index];
        final bool hasBadge =
            progress.badgeName != null && progress.badgeName!.isNotEmpty;

        // Format date manually without intl package
        final d = progress.completedAt;
        final dateStr =
            '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} - ${d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour)}:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'م' : 'ص'}';

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppColors.border_radius),
            border: Border.all(color: AppColors.inputBorder, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: hasBadge
                      ? AppColors.tertiary.withValues(alpha: 0.12)
                      : AppColors.secondary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasBadge
                      ? Icons.workspace_premium_rounded
                      : Icons.task_alt_rounded,
                  color: hasBadge ? AppColors.tertiary : AppColors.secondary,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasBadge
                          ? 'حصل على ${progress.badgeName}'
                          : 'أكمل المهمة',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      progress.missionTitle ?? 'مهمة مجهولة',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Text(
                        '+${progress.starsReward ?? 0}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.star_rounded,
                        color: AppColors.primary,
                        size: 18,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    dateStr,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
