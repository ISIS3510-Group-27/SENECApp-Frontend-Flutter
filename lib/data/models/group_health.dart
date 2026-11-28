import 'dart:math';

class HealthWeek {
  const HealthWeek({required this.weekStart, required this.attendance});

  factory HealthWeek.fromJson(Map<String, dynamic> json) => HealthWeek(
    weekStart: DateTime.parse(json['week_start'] as String),
    attendance: json['attendance'] as int,
  );

  final DateTime weekStart;
  final int attendance;
}

class HealthCase {
  const HealthCase({
    required this.arm,
    required this.status,
    required this.detectedAt,
    required this.lapsedMembers,
    required this.returnedMembers,
    this.returnRate,
  });

  factory HealthCase.fromJson(Map<String, dynamic> json) => HealthCase(
    arm: json['arm'] as String,
    status: json['status'] as String,
    detectedAt: DateTime.parse(json['detected_at'] as String),
    lapsedMembers: json['lapsed_members'] as int,
    returnedMembers: json['returned_members'] as int,
    returnRate: (json['return_rate'] as num?)?.toDouble(),
  );

  final String arm;
  final String status;
  final DateTime detectedAt;
  final int lapsedMembers;
  final int returnedMembers;
  final double? returnRate;

  bool get active => status == 'active';
}

class ReengagementRate {
  const ReengagementRate({
    required this.arm,
    required this.groups,
    required this.lapsed,
    required this.returned,
    this.rate,
  });

  factory ReengagementRate.fromJson(Map<String, dynamic> json) =>
      ReengagementRate(
        arm: json['arm'] as String,
        groups: json['groups'] as int,
        lapsed: json['lapsed'] as int,
        returned: json['returned'] as int,
        rate: (json['return_to_attendance_rate'] as num?)?.toDouble(),
      );

  final String arm;
  final int groups;
  final int lapsed;
  final int returned;
  final double? rate;
}

String armLabel(String arm) => switch (arm) {
  'event_reminders' => 'Event reminders',
  'group_messages' => 'Group messages',
  _ => arm,
};

class GroupHealth {
  const GroupHealth({
    required this.question,
    required this.answer,
    required this.weeks,
    required this.baseline,
    required this.recent,
    required this.declinePct,
    required this.declining,
    required this.arms,
    this.reengagement,
  });

  factory GroupHealth.fromJson(Map<String, dynamic> json) => GroupHealth(
    question: json['question'] as String,
    answer: json['answer'] as String,
    weeks: [
      for (final week in json['weeks'] as List)
        HealthWeek.fromJson(week as Map<String, dynamic>),
    ],
    baseline: (json['baseline'] as num).toDouble(),
    recent: (json['recent'] as num).toDouble(),
    declinePct: (json['decline_pct'] as num).toDouble(),
    declining: json['declining'] as bool,
    reengagement: json['case'] == null
        ? null
        : HealthCase.fromJson(json['case'] as Map<String, dynamic>),
    arms: [
      for (final arm in json['arms'] as List)
        ReengagementRate.fromJson(arm as Map<String, dynamic>),
    ],
  );

  final String question;
  final String answer;
  final List<HealthWeek> weeks;
  final double baseline;
  final double recent;
  final double declinePct;
  final bool declining;
  final HealthCase? reengagement;
  final List<ReengagementRate> arms;

  List<int> get attendance => [for (final week in weeks) week.attendance];
}

class HealthTrend {
  const HealthTrend({
    required this.average,
    required this.peak,
    required this.lastChange,
  });

  static const window = 3;

  final List<double> average;
  final int peak;
  final double? lastChange;

  static HealthTrend of(List<int> weeks) {
    final average = <double>[];
    for (var i = 0; i < weeks.length; i++) {
      final from = max(0, i - window + 1);
      final slice = weeks.sublist(from, i + 1);
      average.add(slice.reduce((a, b) => a + b) / slice.length);
    }
    final peak = weeks.isEmpty ? 0 : weeks.reduce(max);
    double? lastChange;
    if (weeks.length >= 2 && weeks[weeks.length - 2] > 0) {
      final before = weeks[weeks.length - 2];
      lastChange = (weeks.last - before) / before;
    }
    return HealthTrend(average: average, peak: peak, lastChange: lastChange);
  }
}
