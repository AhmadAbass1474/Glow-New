import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../content/domain/entities/child_progress_entity.dart';
import '../../../content/domain/repositories/content_repository.dart';
import '../../../dashboard/presentation/screens/parent_reports_screen.dart';

class ChildOverviewScreen extends StatefulWidget {
  const ChildOverviewScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.subtitle,
  });

  final String childId;
  final String childName;
  final String? subtitle;

  @override
  State<ChildOverviewScreen> createState() => _ChildOverviewScreenState();
}

class _ChildOverviewScreenState extends State<ChildOverviewScreen> {
  var _loading = true;
  var _missions = 0;
  var _stars = 0;
  var _badges = 0;
  List<ChildProgressEntity> _progress = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await sl<ContentRepository>().getCompletedMissions(widget.childId);
    if (!mounted) return;
    result.fold((_) {
      setState(() => _loading = false);
    }, (list) {
      list.sort((a, b) => b.completedAt.compareTo(a.completedAt));
      var stars = 0;
      var badges = 0;
      for (final item in list) {
        stars += (item.starsReward ?? 0).toInt();
        if (item.badgeName != null && item.badgeName!.isNotEmpty) badges++;
      }
      setState(() {
        _progress = list;
        _missions = list.length;
        _stars = stars;
        _badges = badges;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.childName,
              style: textTheme.titleLarge?.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
              Text(
                widget.subtitle!,
                style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
              ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
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
                    extra: ParentReportArgs(
                      childId: widget.childId,
                      childName: widget.childName,
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(AppColors.border_radius),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    'تقارير',
                    style: textTheme.titleMedium?.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const ShimmerLoading(type: ShimmerType.list)
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(10),
                children: [
                  Text(
                    _missions == 0
                        ? 'لم يبدأ أي مهمات بعد.'
                        : 'أكمل $_missions مهمات، وجمع $_stars نقطة و$_badges أوسمة.',
                    style: textTheme.bodyLarge?.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _Metric(title: 'المهمات', value: '$_missions')),
                      const SizedBox(width: 10),
                      Expanded(child: _Metric(title: 'النقاط', value: '$_stars')),
                      const SizedBox(width: 10),
                      Expanded(child: _Metric(title: 'الأوسمة', value: '$_badges')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'كل الإنجازات',
                    style: textTheme.titleMedium?.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_progress.isEmpty)
                    const _Empty(text: 'لا توجد إنجازات بعد')
                  else
                    for (final item in _progress) ...[
                      _Achievement(item: item),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
            ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
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
          Text(
            value,
            style: textTheme.titleLarge?.copyWith(
              color: AppColors.secondary,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            title,
            style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
          ),
        ],
      ),
    );
  }
}

class _Achievement extends StatelessWidget {
  const _Achievement({required this.item});

  final ChildProgressEntity item;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final badge = item.badgeName;
    final hasBadge = badge != null && badge.isNotEmpty;
    final d = item.completedAt.toLocal();
    final date =
        '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.border_radius),
        border: Border.all(color: AppColors.inputBorder, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.missionTitle ?? 'مهمة',
                  style: textTheme.titleMedium?.copyWith(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  hasBadge ? 'وسام $badge · $date' : date,
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
                ),
              ],
            ),
          ),
          Text(
            '+${item.starsReward ?? 0}',
            style: textTheme.titleMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.border_radius),
        border: Border.all(color: AppColors.inputBorder, width: 1.5),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: AppColors.secondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
