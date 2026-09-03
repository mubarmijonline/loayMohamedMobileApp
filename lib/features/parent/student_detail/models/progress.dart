import 'package:equatable/equatable.dart';

class SubjectProgress extends Equatable {
  const SubjectProgress({
    required this.id,
    required this.name,
    required this.absenceCount,
    this.gradePercent,
  });

  final String id;
  final String name;
  final double? gradePercent;
  final int absenceCount;

  factory SubjectProgress.fromJson(Map<String, dynamic> j) => SubjectProgress(
        id: (j['id'] ?? j['_id'] ?? '').toString(),
        name: (j['name'] ?? '—').toString(),
        gradePercent: _asDouble(j['grade_percent']),
        absenceCount: _asInt(j['absence_count']) ?? 0,
      );

  static double? _asDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  @override
  List<Object?> get props => [id, name, gradePercent, absenceCount];
}

class ProgressReport extends Equatable {
  const ProgressReport({required this.subjects, this.overallPercent});

  final double? overallPercent;
  final List<SubjectProgress> subjects;

  factory ProgressReport.fromJson(Map<String, dynamic> j) => ProgressReport(
        overallPercent: SubjectProgress._asDouble(j['overall_percent']),
        subjects: ((j['subjects'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => SubjectProgress.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
      );

  @override
  List<Object?> get props => [overallPercent, subjects];
}
