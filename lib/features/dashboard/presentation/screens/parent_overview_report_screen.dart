import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/child_activity.dart';

class ParentOverviewReportScreen extends StatelessWidget {
  const ParentOverviewReportScreen({
    super.key,
    required this.childName,
    required this.days,
  });

  final String childName;
  final List<DayReport> days;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final period = PeriodReport(days);
    final name = childName.trim().isEmpty ? 'الابن' : childName.trim();
    final answers = period.eventsOf('answer');
    final right = answers.where((event) => event.isCorrect == true).length;
    final wrong = answers.where((event) => event.isCorrect == false).length;
    final stars = period.eventsOf('reward').fold<int>(0, (sum, event) => sum + event.stars);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'التقرير الشامل',
          style: textTheme.titleLarge?.copyWith(
            color: AppColors.secondary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 32),
        children: [
          Text(
            name,
            style: textTheme.headlineSmall?.copyWith(
              color: AppColors.secondary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'ملخص كل الأيام المعروضة، من الأحدث إلى الأقدم.',
            style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
          ),
          const SizedBox(height: 16),
          _Panel(
            child: Text(
              periodNarrative(period, name),
              style: textTheme.bodyLarge?.copyWith(
                color: AppColors.onSurface,
                height: 1.6,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Stat(label: 'أيام الدخول', value: '${period.presentDays.length}'),
              const SizedBox(width: 8),
              _Stat(label: 'أيام الغياب', value: '${period.absentDays.length}'),
              const SizedBox(width: 8),
              _Stat(label: 'النقاط', value: '$stars'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _Stat(label: 'إجابات صحيحة', value: '$right', tone: AppColors.tertiary),
              const SizedBox(width: 8),
              _Stat(label: 'أخطاء', value: '$wrong', tone: AppColors.burgundy),
            ],
          ),
          const SizedBox(height: 20),
          _Section(
            index: '١',
            title: 'الحضور',
            child: Column(
              children: [
                for (final day in days)
                  _Row(
                    title: '${dayHeadline(day.day)} · ${dayDateLabel(day.day)}',
                    detail: day.visited ? daySummary(day) : 'ما دخل',
                    tone: day.visited ? AppColors.tertiary : AppColors.secondary,
                  ),
              ],
            ),
          ),
          _Section(
            index: '٢',
            title: 'وين تحرّك',
            child: _movement(period, textTheme),
          ),
          _Section(
            index: '٣',
            title: 'شو تعلّم',
            child: _stories(period, textTheme),
          ),
          _Section(
            index: '٤',
            title: 'الاختبار',
            child: _quiz(period, textTheme),
          ),
          _Section(
            index: '٥',
            title: 'شو كسب',
            child: _rewards(period, textTheme),
          ),
          _Section(
            index: '٦',
            title: 'يحتاج يتحسّن',
            tint: AppColors.primaryContainer,
            child: Text(
              periodImprovement(period),
              style: textTheme.bodyLarge?.copyWith(
                color: AppColors.secondary,
                height: 1.6,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _movement(PeriodReport period, TextTheme textTheme) {
    final steps = period.eventsOf('world') + period.eventsOf('mission') + period.eventsOf('move');
    if (steps.isEmpty) {
      return Text('ما في تنقّل مسجّل.', style: textTheme.bodyMedium);
    }
    final worlds = <String, int>{};
    final missions = <String, String>{};
    for (final event in period.eventsOf('world')) {
      worlds[event.title] = (worlds[event.title] ?? 0) + 1;
    }
    for (final event in period.eventsOf('mission')) {
      missions[event.title] = event.body;
    }
    return Column(
      children: [
        for (final title in worlds.keys)
          _Row(
            title: 'عالم $title',
            detail: 'فتحه ${worlds[title]} مرة',
          ),
        for (final title in missions.keys)
          _Row(
            title: 'مهمة $title',
            detail: missions[title]!.isEmpty ? null : 'من عالم ${missions[title]}',
          ),
        if (period.eventsOf('move').isNotEmpty)
          const _Row(title: 'فتح صفحة الأوسمة', detail: null),
      ],
    );
  }

  Widget _stories(PeriodReport period, TextTheme textTheme) {
    final stories = period.eventsOf('story');
    if (stories.isEmpty) {
      return Text('ما في قصص مسجّلة.', style: textTheme.bodyMedium);
    }
    final seen = <String>{};
    return Column(
      children: [
        for (final event in stories)
          if (seen.add('${event.missionId}|${event.title}'))
            _Row(
              title: event.title,
              detail: event.body.isEmpty ? null : event.body,
            ),
      ],
    );
  }

  Widget _quiz(PeriodReport period, TextTheme textTheme) {
    final answers = period.eventsOf('answer');
    if (answers.isEmpty) {
      return Text('ما في اختبار مسجّل في هذه الفترة.', style: textTheme.bodyMedium);
    }
    final groups = <String, List<ActivityEvent>>{};
    for (final event in answers) {
      groups.putIfAbsent(event.title, () => []).add(event);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final title in groups.keys) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Text(
              title,
              style: textTheme.titleSmall?.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          for (final event in groups[title]!) ...[
            _Answer(event: event),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  Widget _rewards(PeriodReport period, TextTheme textTheme) {
    final rewards = period.eventsOf('reward');
    if (rewards.isEmpty) {
      return Text('ما في مهام مكتملة ولا نقاط.', style: textTheme.bodyMedium);
    }
    return Column(
      children: [
        for (final event in rewards)
          _Row(
            title: event.title,
            detail: [
              dayDateLabel(event.at),
              if (event.stars > 0) '${event.stars} نقطة',
              if (event.body.trim().isNotEmpty) 'وسام ${event.body.trim()}',
            ].join(' · '),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = tone ?? AppColors.secondary;
    return Expanded(
      child: Container(
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
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

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
      child: child,
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
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
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.detail, this.tone});

  final String title;
  final String? detail;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.bodyLarge?.copyWith(
              color: tone ?? AppColors.onSurface,
              fontWeight: FontWeight.w800,
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
    );
  }
}

class _Answer extends StatelessWidget {
  const _Answer({required this.event});

  final ActivityEvent event;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final correct = event.isCorrect == true;
    final tone = correct ? AppColors.tertiary : AppColors.burgundy;
    return Container(
      width: double.infinity,
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
            '${dayHeadline(event.at)} · ${dayDateLabel(event.at)} · ${dayClock(event.at)}',
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
          const SizedBox(height: 6),
          Text(
            'إجابته: ${event.chosen ?? ''}',
            style: textTheme.bodyMedium?.copyWith(color: tone, fontWeight: FontWeight.w800),
          ),
          Text(
            'الإجابة الصح: ${event.correct ?? ''}',
            style: textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
          ),
          const SizedBox(height: 4),
          Text(
            correct ? 'صحيحة' : 'خاطئة',
            style: textTheme.labelLarge?.copyWith(color: tone, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}
