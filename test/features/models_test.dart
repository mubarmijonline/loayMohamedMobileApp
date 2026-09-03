import 'package:flutter_test/flutter_test.dart';
import 'package:loay_mohamed_elearning/features/_shared/models.dart';

void main() {
  test('Subject parses snake_case and percentages > 1', () {
    final s = Subject.fromJson({
      'id': '7',
      'name': 'Math',
      'completion_percent': 42, // server may send 0..100
      'lessons': '12',
      'enrollment_status': 'active',
    });
    expect(s.id, '7');
    expect(s.name, 'Math');
    expect(s.completionPercent, closeTo(0.42, 1e-9));
    expect(s.lessonsCount, 12);
    expect(s.enrollmentStatus, 'active');
  });

  test('Assignment is overdue when due is past and not submitted', () {
    final a = Assignment.fromJson({
      'id': '1',
      'title': 'HW',
      'type': 'homework',
      'due_at': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
    });
    expect(a.isOverdue, isTrue);
  });

  test('NotificationItem parses read_at presence', () {
    final n = NotificationItem.fromJson({
      'id': '1',
      'title': 't',
      'body': 'b',
      'created_at': DateTime.now().toIso8601String(),
      'read_at': DateTime.now().toIso8601String(),
    });
    expect(n.read, isTrue);
  });

  test('StudentDashboard derives overall completion when missing', () {
    final d = StudentDashboard.fromJson({
      'subjects': [
        {'id': 1, 'name': 'A', 'completion_percent': 50},
        {'id': 2, 'name': 'B', 'completion_percent': 100},
      ],
    });
    expect(d.subjects, hasLength(2));
    expect(d.overallCompletion, closeTo(0.75, 1e-9));
  });
}
