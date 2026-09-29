import 'package:flutter/material.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/shimmer_loading.dart';
import '../../../content/domain/repositories/content_repository.dart';
import '../../data/child_activity.dart';
import 'parent_overview_report_screen.dart';

class ParentReportArgs {
  const ParentReportArgs({this.childId, this.childName});

  final String? childId;
  final String? childName;
}

class ParentReportsScreen extends StatefulWidget {
  const ParentReportsScreen({super.key, required this.args});

  final ParentReportArgs args;

  @override
  State<ParentReportsScreen> createState() => _ParentReportsScreenState();
}

class _ParentReportsScreenState extends State<ParentReportsScreen> {
  var _loading = true;
  List<DayReport> _days = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final childId = widget.args.childId;
    if (childId == null || childId.isEmpty) {
      if (mounted) {
        setState(() {
          _days = const [];
          _loading = false;
        });
      }
      return;
    }

    var events = <ActivityEvent>[];
    try {
      events = await sl<ChildActivityLogger>().fetch(childId);
    } catch (_) {}

    try {
      final progress = await sl<ContentRepository>().getCompletedMissions(childId);
      progress.fold((_) {}, (list) {
        events = mergeMissionRewards(
          events: events,
          rewards: [
            for (final item in list)
              (
                at: item.completedAt.toLocal(),
                missionId: item.missionId,
                title: item.missionTitle ?? 'مهمة',
                badge: item.badgeName ?? '',
                stars: item.starsReward ?? 0,
              ),
          ],
        );
      });
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _days = buildDayReports(events);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final name = widget.args.childName;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'التقارير',
              style: textTheme.titleLarge?.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (name != null && name.isNotEmpty)
              Text(
                name,
                style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
              ),
          ],
        ),
      ),
      body: _loading
          ? const ShimmerLoading(type: ShimmerType.list)
          : widget.args.childId == null || widget.args.childId!.isEmpty
          ? const _NoChild()
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _load,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 24),
                itemCount: _days.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ParentOverviewReportScreen(
                                  childName: name ?? '',
                                  days: _days,
                                ),
                              ),
                            );
                          },
                          child: const Text('التقرير الشامل'),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'هذي أيام ${name == null || name.isEmpty ? 'الابن' : name}، من الأحدث. البطاقة تعني: استخدم التطبيق في ذلك اليوم أو لا. اضغط اليوم اللي فيه نشاط عشان تشوف التفاصيل.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppColors.secondary,
                            height: 1.5,
                          ),
                        ),
                      ],
                    );
                  }
                  final report = _days[index - 1];
                  return _DayCard(
                    report: report,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ParentReportDayScreen(
                            childName: name ?? '',
                            report: report,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
    );
  }
}

class _NoChild extends StatelessWidget {
  const _NoChild();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          'ما في ابن مختار. اربط ابناً من الإعدادات، وبعدها هالصفحة تعرض أيامه.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: AppColors.secondary,
            height: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.report, required this.onTap});

  final DayReport report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final quiet = !report.visited;
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppColors.border_radius),
        side: const BorderSide(color: AppColors.inputBorder, width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppColors.border_radius),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dayHeadline(report.day),
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppColors.secondary,
                      ),
                    ),
                    Text(
                      dayDateLabel(report.day),
                      style: textTheme.bodySmall?.copyWith(color: AppColors.secondary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      daySummary(report),
                      style: textTheme.bodyMedium?.copyWith(
                        color: quiet ? AppColors.secondary : AppColors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                quiet ? Icons.remove_circle_outline : Icons.arrow_forward_ios,
                color: AppColors.secondary,
                size: quiet ? 22 : 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ParentReportDayScreen extends StatelessWidget {
  const ParentReportDayScreen({
    super.key,
    required this.childName,
    required this.report,
  });

  final String childName;
  final DayReport report;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          '${dayHeadline(report.day)} · ${dayDateLabel(report.day)}',
          style: textTheme.titleMedium?.copyWith(
            color: AppColors.secondary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 28),
        children: [
          if (childName.isNotEmpty)
            Text(
              childName,
              style: textTheme.titleLarge?.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.w900,
              ),
            ),
          const SizedBox(height: 12),
          _Block(
            index: '١',
            title: 'هل دخل اليوم؟',
            child: Text(
              report.visited
                  ? daySummary(report)
                  : '${daySummary(report)}. ما في حركة ولا قصة ولا اختبار ولا نقاط في هذا اليوم.',
              style: textTheme.bodyLarge?.copyWith(
                color: AppColors.onSurface,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (report.visited) ...[
            _timeline(context),
            _stories(context),
            _quiz(context),
            _rewards(context),
          ],
          _Block(
            index: report.visited ? '٦' : '٢',
            title: 'يحتاج يتحسّن',
            tint: AppColors.primaryContainer,
            child: Text(
              improvementNote(report),
              style: textTheme.bodyLarge?.copyWith(
                color: AppColors.secondary,
                height: 1.6,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeline(BuildContext context) {
    final steps = report.events.where((event) {
      return event.kind == 'enter' ||
          event.kind == 'world' ||
          event.kind == 'mission' ||
          event.kind == 'move';
    }).toList();
    if (steps.isEmpty) return const SizedBox.shrink();
    return _Block(
      index: '٢',
      title: 'وين تحرّك',
      child: Column(
        children: [
          for (final event in steps) _Line(
            time: dayClock(event.at),
            title: _moveTitle(event),
            detail: event.kind == 'mission' && event.body.isNotEmpty ? 'من عالم ${event.body}' : null,
          ),
        ],
      ),
    );
  }

  Widget _stories(BuildContext context) {
    final stories = report.ofKind('story');
    if (stories.isEmpty) return const SizedBox.shrink();
    return _Block(
      index: '٣',
      title: 'شو تعلّم',
      child: Column(
        children: [
          for (final event in stories)
            _Line(
              time: dayClock(event.at),
              title: event.title,
              detail: event.body.isEmpty ? null : event.body,
            ),
        ],
      ),
    );
  }

  Widget _quiz(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final starts = report.ofKind('quiz');
    final answers = report.ofKind('answer');
    if (starts.isEmpty && answers.isEmpty) return const SizedBox.shrink();
    return _Block(
      index: '٤',
      title: 'الاختبار',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final event in starts)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${dayClock(event.at)} · بدأ اختبار «${event.title}»',
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          for (var index = 0; index < answers.length; index++) ...[
            if (index > 0) const SizedBox(height: 10),
            _AnswerCard(event: answers[index]),
          ],
        ],
      ),
    );
  }

  Widget _rewards(BuildContext context) {
    final rewards = report.ofKind('reward');
    if (rewards.isEmpty) return const SizedBox.shrink();
    return _Block(
      index: '٥',
      title: 'شو كسب',
      child: Column(
        children: [
          for (final event in rewards)
            _Line(
              time: dayClock(event.at),
              title: 'أنهى «${event.title}»',
              detail: [
                if (event.stars > 0) '${event.stars} نقطة',
                if (event.body.trim().isNotEmpty) 'وسام ${event.body.trim()}',
              ].join(' · '),
            ),
        ],
      ),
    );
  }

  String _moveTitle(ActivityEvent event) {
    switch (event.kind) {
      case 'enter':
        return 'دخل التطبيق';
      case 'world':
        return 'فتح عالم ${event.title}';
      case 'mission':
        return 'دخل مهمة ${event.title}';
      case 'move':
        return event.title;
      default:
        return event.title;
    }
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.index,
    required this.title,
    required this.child,
    this.tint,
  });

  final String index;
  final String title;
  final Widget child;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tint ?? AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.border_radius),
        border: Border.all(color: AppColors.inputBorder, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppColors.border_radius),
                ),
                child: Text(
                  index,
                  style: textTheme.labelLarge?.copyWith(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: textTheme.titleMedium?.copyWith(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.time, required this.title, this.detail});

  final String time;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              time,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.bodyLarge?.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (detail != null && detail!.trim().isNotEmpty)
                  Text(
                    detail!,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.secondary,
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
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.event});

  final ActivityEvent event;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final correct = event.isCorrect == true;
    final tone = correct ? AppColors.tertiary : AppColors.burgundy;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppColors.border_radius),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${dayClock(event.at)} · ${event.title}',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.secondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            event.question ?? '',
            style: textTheme.titleSmall?.copyWith(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w800,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'إجابته: ${event.chosen ?? ''}',
            style: textTheme.bodyMedium?.copyWith(
              color: tone,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            'الإجابة الصح: ${event.correct ?? ''}',
            style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
          ),
          const SizedBox(height: 4),
          Text(
            correct ? 'صحيحة' : 'خاطئة',
            style: textTheme.labelLarge?.copyWith(
              color: tone,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
