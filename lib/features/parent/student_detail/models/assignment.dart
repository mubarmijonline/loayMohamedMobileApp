import 'package:equatable/equatable.dart';

/// Parent-portal view of a single student assignment.
class Assignment extends Equatable {
  const Assignment({
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
  final String status; // pending | submitted | graded | late
  final DateTime? dueDate;
  final DateTime? submittedAt;
  final int? grade;
  final int? maxGrade;

  factory Assignment.fromJson(Map<String, dynamic> j) => Assignment(
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
