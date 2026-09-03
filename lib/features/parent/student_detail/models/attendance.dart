import 'package:equatable/equatable.dart';

class AttendanceSummary extends Equatable {
  const AttendanceSummary({
    required this.present,
    required this.absent,
    required this.late,
    required this.total,
  });

  final int present;
  final int absent;
  final int late;
  final int total;

  factory AttendanceSummary.fromJson(Map<String, dynamic> j) =>
      AttendanceSummary(
        present: _i(j['present']),
        absent: _i(j['absent']),
        late: _i(j['late']),
        total: _i(j['total']),
      );

  static int _i(Object? v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  @override
  List<Object?> get props => [present, absent, late, total];
}

class AttendanceRecord extends Equatable {
  const AttendanceRecord({
    required this.date,
    required this.status,
    required this.subjectName,
    this.classId,
  });

  final String date; // YYYY-MM-DD
  final String status; // present | absent | late
  final String subjectName;
  final String? classId;

  DateTime? get dateTime => DateTime.tryParse(date);

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
        date: (j['date'] ?? '').toString(),
        status: (j['status'] ?? 'present').toString(),
        subjectName: (j['subject_name'] ?? '—').toString(),
        classId: j['class_id']?.toString(),
      );

  @override
  List<Object?> get props => [date, status, subjectName, classId];
}

class AttendanceData extends Equatable {
  const AttendanceData({
    required this.month,
    required this.summary,
    required this.attendanceRate,
    required this.records,
  });

  final String month;
  final AttendanceSummary summary;
  final double attendanceRate;
  final List<AttendanceRecord> records;

  factory AttendanceData.fromJson(Map<String, dynamic> j) {
    final summaryMap = j['summary'];
    final summary = summaryMap is Map
        ? AttendanceSummary.fromJson(Map<String, dynamic>.from(summaryMap))
        : AttendanceSummary(
            present: AttendanceSummary._i(j['present']),
            absent: AttendanceSummary._i(j['absent']),
            late: AttendanceSummary._i(j['late']),
            total: AttendanceSummary._i(j['total_days']),
          );
    return AttendanceData(
      month: (j['month'] ?? '').toString(),
      summary: summary,
      attendanceRate:
          (j['attendance_rate'] is num) ? (j['attendance_rate'] as num).toDouble() : 0.0,
      records: ((j['records'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => AttendanceRecord.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [month, summary, attendanceRate, records];
}
