import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/data/datasources/auth_local_data_source.dart';

class ActivityEvent {
  const ActivityEvent({
    required this.at,
    required this.kind,
    required this.title,
    this.body = '',
    this.missionId,
    this.question,
    this.chosen,
    this.correct,
    this.isCorrect,
    this.stars = 0,
  });

  final DateTime at;
  final String kind;
  final String title;
  final String body;
  final String? missionId;
  final String? question;
  final String? chosen;
  final String? correct;
  final bool? isCorrect;
  final int stars;

  factory ActivityEvent.fromRow(Map<String, dynamic> row) {
    return ActivityEvent(
      at: DateTime.tryParse('${row['created_at']}')?.toLocal() ?? DateTime.now(),
      kind: '${row['kind'] ?? ''}',
      title: '${row['title'] ?? ''}',
      body: '${row['body'] ?? ''}',
      missionId: row['mission_id'] as String?,
      question: row['question'] as String?,
      chosen: row['chosen_answer'] as String?,
      correct: row['correct_answer'] as String?,
      isCorrect: row['is_correct'] as bool?,
      stars: (row['stars'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toRow(String childId) {
    return {
      'child_id': childId,
      'kind': kind,
      'title': title,
      'body': body,
      'mission_id': missionId,
      'question': question,
      'chosen_answer': chosen,
      'correct_answer': correct,
      'is_correct': isCorrect,
      'stars': stars,
      'created_at': at.toUtc().toIso8601String(),
    };
  }
}

class DayReport {
  const DayReport({required this.day, required this.events});

  final DateTime day;
  final List<ActivityEvent> events;

  bool get visited => events.isNotEmpty;

  List<ActivityEvent> ofKind(String kind) {
    return events.where((event) => event.kind == kind).toList();
  }
}

class ChildActivityLogger {
  ChildActivityLogger(this._box, this._client, this._local);

  final Box _box;
  final SupabaseClient _client;
  final AuthLocalDataSource _local;

  static const _pendingKey = 'child_activity_pending';

  Future<void> entered() {
    return _record(const _Draft(kind: 'enter', title: 'دخل التطبيق'));
  }

  Future<void> openedWorld(String title) {
    return _record(_Draft(kind: 'world', title: title, body: 'فتح هذا العالم'));
  }

  Future<void> openedMission({required String missionId, required String title, required String world}) {
    return _record(_Draft(
      kind: 'mission',
      title: title,
      body: world,
      missionId: missionId,
    ));
  }

  Future<void> openedBadges() {
    return _record(const _Draft(kind: 'move', title: 'فتح الأوسمة'));
  }

  Future<void> watchedStory({
    required String missionId,
    required String missionTitle,
    required String storyTitle,
    required String content,
  }) {
    return _record(_Draft(
      kind: 'story',
      title: storyTitle.isEmpty ? missionTitle : storyTitle,
      body: _clip(content),
      missionId: missionId,
    ));
  }

  Future<void> startedQuiz({required String missionId, required String title}) {
    return _record(_Draft(
      kind: 'quiz',
      title: title,
      body: 'بدأ الاختبار',
      missionId: missionId,
    ));
  }

  Future<void> answered({
    required String missionId,
    required String missionTitle,
    required String question,
    required String chosen,
    required String correct,
    required bool isCorrect,
  }) {
    return _record(_Draft(
      kind: 'answer',
      title: missionTitle,
      missionId: missionId,
      question: question,
      chosen: chosen,
      correct: correct,
      isCorrect: isCorrect,
    ));
  }

  Future<void> finishedMission({
    required String missionId,
    required String title,
    required String badgeName,
    required int stars,
  }) {
    return _record(_Draft(
      kind: 'reward',
      title: title,
      body: badgeName,
      missionId: missionId,
      stars: stars,
    ));
  }

  Future<List<ActivityEvent>> fetch(String childId) async {
    await flush();
    final rows = await _client
        .from('child_activity')
        .select()
        .eq('child_id', childId)
        .order('created_at');
    return [
      for (final row in rows) ActivityEvent.fromRow(Map<String, dynamic>.from(row)),
    ];
  }

  Future<void> flush() async {
    final pending = _readPending();
    if (pending.isEmpty) return;
    final kept = <Map<String, dynamic>>[];
    for (final row in pending) {
      try {
        await _client.from('child_activity').insert(row);
      } catch (_) {
        kept.add(row);
      }
    }
    await _box.put(_pendingKey, jsonEncode(kept));
  }

  Future<void> _record(_Draft draft) async {
    try {
      final child = await _local.getLastChild();
      final childId = child?.id ?? _client.auth.currentUser?.id;
      if (childId == null || childId.isEmpty) return;
      if (draft.kind == 'enter' && !_shouldLogEnter(childId)) return;
      final row = draft.event(DateTime.now()).toRow(childId);
      final pending = _readPending()..add(row);
      await _box.put(_pendingKey, jsonEncode(pending));
      await flush();
    } catch (_) {}
  }

  bool _shouldLogEnter(String childId) {
    final key = 'child_activity_enter_$childId';
    final last = _box.get(key);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (last is int && now - last < const Duration(minutes: 30).inMilliseconds) {
      return false;
    }
    _box.put(key, now);
    return true;
  }

  List<Map<String, dynamic>> _readPending() {
    final raw = _box.get(_pendingKey);
    if (raw is! String || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return [
      for (final item in decoded)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }
}

class _Draft {
  const _Draft({
    required this.kind,
    required this.title,
    this.body = '',
    this.missionId,
    this.question,
    this.chosen,
    this.correct,
    this.isCorrect,
    this.stars = 0,
  });

  final String kind;
  final String title;
  final String body;
  final String? missionId;
  final String? question;
  final String? chosen;
  final String? correct;
  final bool? isCorrect;
  final int stars;

  ActivityEvent event(DateTime at) {
    return ActivityEvent(
      at: at,
      kind: kind,
      title: title,
      body: body,
      missionId: missionId,
      question: question,
      chosen: chosen,
      correct: correct,
      isCorrect: isCorrect,
      stars: stars,
    );
  }
}

String _clip(String value) {
  final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.length <= 140) return compact;
  return '${compact.substring(0, 140)}…';
}

List<DayReport> buildDayReports(List<ActivityEvent> events) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final grouped = <DateTime, List<ActivityEvent>>{};
  for (var offset = 0; offset < 14; offset++) {
    grouped[today.subtract(Duration(days: offset))] = [];
  }
  for (final event in events) {
    final day = DateTime(event.at.year, event.at.month, event.at.day);
    if (today.difference(day).inDays > 60 || day.isAfter(today)) continue;
    grouped.putIfAbsent(day, () => []).add(event);
  }
  final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final day in days)
      DayReport(
        day: day,
        events: [...grouped[day]!]..sort((a, b) => a.at.compareTo(b.at)),
      ),
  ];
}

List<ActivityEvent> mergeMissionRewards({
  required List<ActivityEvent> events,
  required List<({DateTime at, String missionId, String title, String badge, int stars})> rewards,
}) {
  final merged = [...events];
  for (final reward in rewards) {
    final day = DateTime(reward.at.year, reward.at.month, reward.at.day);
    final already = merged.any((event) {
      if (event.kind != 'reward' || event.missionId != reward.missionId) return false;
      final eventDay = DateTime(event.at.year, event.at.month, event.at.day);
      return eventDay == day;
    });
    if (already) continue;
    merged.add(ActivityEvent(
      at: reward.at,
      kind: 'reward',
      title: reward.title,
      body: reward.badge,
      missionId: reward.missionId,
      stars: reward.stars,
    ));
  }
  return merged;
}

String dayHeadline(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(day.year, day.month, day.day);
  if (target == today) return 'اليوم';
  if (target == today.subtract(const Duration(days: 1))) return 'أمس';
  const names = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
  return names[target.weekday - 1];
}

String dayDateLabel(DateTime day) {
  const months = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];
  return '${day.day} ${months[day.month - 1]}';
}

String dayClock(DateTime time) {
  final hour = time.hour;
  final shown = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
  final minute = time.minute.toString().padLeft(2, '0');
  final suffix = hour >= 12 ? 'م' : 'ص';
  return '$shown:$minute $suffix';
}

String daySummary(DayReport report) {
  if (!report.visited) {
    final headline = dayHeadline(report.day);
    if (headline == 'اليوم') return 'ما دخل الابن اليوم';
    if (headline == 'أمس') return 'ما دخل الابن أمس';
    return 'ما دخل الابن في هذا اليوم';
  }
  final wrong = report.ofKind('answer').where((event) => event.isCorrect == false).length;
  final right = report.ofKind('answer').where((event) => event.isCorrect == true).length;
  final stars = report.ofKind('reward').fold<int>(0, (sum, event) => sum + event.stars);
  final parts = <String>['دخل'];
  if (right + wrong > 0) {
    parts.add('$right إجابة صحيحة');
    parts.add('$wrong خطأ');
  } else if (report.ofKind('story').isNotEmpty) {
    parts.add('تابع القصص');
  } else {
    parts.add('تصفّح بدون اختبار');
  }
  if (stars > 0) parts.add('كسب $stars نقطة');
  return parts.join(' · ');
}

class PeriodReport {
  const PeriodReport(this.days);

  final List<DayReport> days;

  List<DayReport> get presentDays => days.where((day) => day.visited).toList();

  List<DayReport> get absentDays => days.where((day) => !day.visited).toList();

  List<ActivityEvent> eventsOf(String kind) {
    return [
      for (final day in days) ...day.ofKind(kind),
    ];
  }
}

String periodNarrative(PeriodReport period, String childName) {
  final name = childName.trim().isEmpty ? 'الابن' : childName.trim();
  final span = period.days.length;
  final present = period.presentDays.length;
  final absent = period.absentDays.length;
  if (present == 0) {
    return 'خلال $span يوم، ما في استخدام مسجّل لـ$name. ما في حركة ولا اختبار ولا نقاط في هذه الفترة.';
  }
  final answers = period.eventsOf('answer');
  final right = answers.where((event) => event.isCorrect == true).length;
  final wrong = answers.where((event) => event.isCorrect == false).length;
  final stars = period.eventsOf('reward').fold<int>(0, (sum, event) => sum + event.stars);
  final missions = period.eventsOf('reward').map((event) => event.title).toSet().length;
  final parts = <String>[
    'خلال $span يوم، دخل $name في $present يوم وغاب $absent.',
  ];
  if (missions > 0) {
    parts.add('أنهى $missions مهمة وكسب $stars نقطة.');
  }
  if (answers.isNotEmpty) {
    parts.add('جاوب ${answers.length} سؤال: $right صحيحة و$wrong خاطئة.');
  } else if (period.eventsOf('story').isNotEmpty) {
    parts.add('تابع القصص وما في اختبار مسجّل.');
  } else {
    parts.add('التصفح موجود، والاختبار غير موجود.');
  }
  return parts.join(' ');
}

String periodImprovement(PeriodReport period) {
  final present = period.presentDays.length;
  final absent = period.absentDays.length;
  if (present == 0) {
    return 'ما في أخطاء لأن التطبيق ما انفتح في هذه الفترة. ابدأ بمهمة واحدة قصيرة، وخلّها تصير عادة يومية.';
  }
  final lines = <String>[];
  if (absent > present) {
    lines.add('الغياب أكثر من الحضور. ثبّت وقتاً قصيراً كل يوم أهم من جلسة طويلة متقطعة.');
  }
  final answers = period.eventsOf('answer');
  if (answers.isEmpty) {
    if (period.eventsOf('story').isNotEmpty) {
      lines.add('في قصص مسموعة بلا اختبار. خلّه يكمّل للأسئلة حتى نعرف شو ثبت.');
    } else {
      lines.add('في دخول بلا اختبار. وجّهه لمهمة واحدة ويخلّصها للنهاية.');
    }
    return lines.join('\n');
  }
  final wrong = answers.where((event) => event.isCorrect == false).toList();
  if (wrong.isEmpty) {
    lines.add('كل الإجابات المسجّلة صحيحة. ثبّت ذلك بإعادة أصعب مهمة مرة بعد يومين، بهدوء.');
    return lines.join('\n');
  }
  final groups = <String, List<ActivityEvent>>{};
  for (final event in wrong) {
    groups.putIfAbsent(event.title, () => []).add(event);
  }
  final names = groups.keys.toList()
    ..sort((a, b) => groups[b]!.length.compareTo(groups[a]!.length));
  lines.add('ابدأ من المهمة التي تكرر خطؤها، ثم السؤال نفسه:');
  for (final name in names) {
    final items = groups[name]!;
    lines.add('«$name»: ${items.length} خطأ.');
    final seen = <String>{};
    for (final item in items) {
      final question = (item.question ?? '').trim();
      final correct = (item.correct ?? '').trim();
      if (question.isEmpty || !seen.add(question)) continue;
      lines.add('• $question — الإجابة الصح: $correct');
    }
  }
  return lines.join('\n');
}

String improvementNote(DayReport report) {
  if (!report.visited) {
    return 'ما استخدم التطبيق اليوم، فما في أخطاء نراجعها. خلّه يفتح مهمة واحدة قصيرة في اليوم الجاي.';
  }
  final answers = report.ofKind('answer');
  if (answers.isEmpty) {
    if (report.ofKind('story').isNotEmpty) {
      return 'سمع القصص وما وصل للاختبار. المرة الجاية خلّه يكمل للأسئلة حتى نعرف شو ثبت معه.';
    }
    return 'فتح التطبيق وتصفّح، وما في اختبار. وجّهه لمهمة واحدة ويخلّصها.';
  }
  final wrong = answers.where((event) => event.isCorrect == false).toList();
  if (wrong.isEmpty) {
    return 'كل إجابات اليوم صحيحة. ثبّت النجاح بإعادة المهمة مرة بعد يومين، بهدوء وبدون ضغط.';
  }
  final groups = <String, List<ActivityEvent>>{};
  for (final event in wrong) {
    groups.putIfAbsent(event.title, () => []).add(event);
  }
  final names = groups.keys.toList()
    ..sort((a, b) => groups[b]!.length.compareTo(groups[a]!.length));
  final lines = <String>[
    'التركيز يكون على الأسئلة التي أخطأ فيها:',
  ];
  for (final name in names) {
    final items = groups[name]!;
    lines.add('في «$name» أخطأ في ${items.length} سؤال.');
    for (final item in items) {
      final question = (item.question ?? '').trim();
      final correct = (item.correct ?? '').trim();
      if (question.isEmpty) continue;
      lines.add('• $question — الإجابة الصح: $correct');
    }
  }
  return lines.join('\n');
}
