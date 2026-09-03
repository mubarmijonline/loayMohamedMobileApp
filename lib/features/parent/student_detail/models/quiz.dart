import 'package:equatable/equatable.dart';

/// Quiz / exam item — same wire-shape as Assignment but different list key.
class Quiz extends Equatable {
  const Quiz({
    required this.id,
    required this.title,
    required this.subject,
    required this.status,
    this.dueDate,
    this.submittedAt,
    this.grade,
    this.maxGrade,
  });

  final String id;
  final String title;
  final String subject;
  final String status;
  final DateTime? dueDate;
  final DateTime? submittedAt;
  final int? grade;
  final int? maxGrade;

  factory Quiz.fromJson(Map<String, dynamic> j) => Quiz(
        id: (j['id'] ?? j['_id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        subject: (j['subject'] ?? j['subject_name'] ?? '—').toString(),
        status: (j['status'] ?? 'pending').toString(),
        dueDate: _parseDate(j['due_date']),
        submittedAt: _parseDate(j['submitted_at']),
        grade: _asInt(j['grade']),
        maxGrade: _asInt(j['max_grade']),
      );

  static DateTime? _parseDate(Object? v) {
    if (v == null) return null;
    final s = v.toString();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  static int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  @override
  List<Object?> get props =>
      [id, title, subject, status, dueDate, submittedAt, grade, maxGrade];
}
