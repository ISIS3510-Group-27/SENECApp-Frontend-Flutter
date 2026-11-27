/// BQ6 for one group: which entry points bring the group its joins
/// (`GET /groups/{id}/insights/join-sources`).
class JoinSource {
  const JoinSource({
    required this.entryPoint,
    required this.views,
    required this.joins,
    this.viewToJoinRate,
    this.shareOfJoins,
    this.campusViewToJoinRate,
  });

  factory JoinSource.fromJson(Map<String, dynamic> json) => JoinSource(
    entryPoint: json['entry_point'] as String,
    views: json['views'] as int,
    joins: json['joins'] as int,
    viewToJoinRate: (json['view_to_join_rate'] as num?)?.toDouble(),
    shareOfJoins: (json['share_of_joins'] as num?)?.toDouble(),
    campusViewToJoinRate: (json['campus_view_to_join_rate'] as num?)
        ?.toDouble(),
  );

  final String entryPoint;
  final int views;
  final int joins;

  /// Joins per profile view from this entry point, for this group.
  final double? viewToJoinRate;

  /// This entry point's part of the group's joins (0-1).
  final double? shareOfJoins;

  /// The same rate for every group on campus, to compare against.
  final double? campusViewToJoinRate;

  Map<String, dynamic> toJson() => {
    'entry_point': entryPoint,
    'views': views,
    'joins': joins,
    'view_to_join_rate': viewToJoinRate,
    'share_of_joins': shareOfJoins,
    'campus_view_to_join_rate': campusViewToJoinRate,
  };
}

class JoinSources {
  const JoinSources({
    required this.question,
    required this.answer,
    required this.campusAnswer,
    required this.days,
    required this.views,
    required this.joins,
    required this.sources,
  });

  factory JoinSources.fromJson(Map<String, dynamic> json) => JoinSources(
    question: json['question'] as String,
    answer: json['answer'] as String,
    campusAnswer: json['campus_answer'] as String,
    days: json['days'] as int,
    views: json['views'] as int,
    joins: json['joins'] as int,
    sources: [
      for (final source in json['sources'] as List)
        JoinSource.fromJson(source as Map<String, dynamic>),
    ],
  );

  final String question;
  final String answer;
  final String campusAnswer;
  final int days;
  final int views;
  final int joins;

  /// Most joins first.
  final List<JoinSource> sources;

  JoinSource? source(String entryPoint) {
    for (final source in sources) {
      if (source.entryPoint == entryPoint) return source;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'question': question,
    'answer': answer,
    'campus_answer': campusAnswer,
    'days': days,
    'views': views,
    'joins': joins,
    'sources': [for (final source in sources) source.toJson()],
  };
}

/// A [JoinSources] answer as it was at [takenAt], kept on the phone.
class JoinSnapshot {
  const JoinSnapshot({required this.takenAt, required this.sources});

  final DateTime takenAt;
  final JoinSources sources;
}
