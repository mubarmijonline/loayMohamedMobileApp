import 'package:flutter_test/flutter_test.dart';
import 'package:loay_mohamed_elearning/features/_shared/models.dart';

void main() {
  test('Subject parses snake_case and percentages > 1', () {
    final s = Subject.fromJson(const {
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
      'due_at':
          DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
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
    final d = StudentDashboard.fromJson(const {
      'subjects': [
        {'id': 1, 'name': 'A', 'completion_percent': 50},
        {'id': 2, 'name': 'B', 'completion_percent': 100},
      ],
    });
    expect(d.subjects, hasLength(2));
    expect(d.overallCompletion, closeTo(0.75, 1e-9));
  });

  _apiBriefContractTests();
}

void _apiBriefContractTests() {
  group('Assignment (API_BRIEF §7)', () {
    test('keeps `overdue` as a real submission_status', () {
      final a = Assignment.fromJson(const {
        '_id': 'a1',
        'title': 'Paper 1',
        'type': 'homework',
        'submission_status': 'overdue',
        'submission_states': ['overdue'],
      });
      // The old model whitelisted {pending,submitted,graded,late} and nulled
      // `overdue` out, so overdue work rendered as "Pending".
      expect(a.status, 'overdue');
      expect(a.isOverdue, isTrue);
    });

    test('`late` rides alongside `submitted`, it is not a status', () {
      final a = Assignment.fromJson(const {
        '_id': 'a2',
        'title': 'Late one',
        'type': 'homework',
        'submission_status': 'submitted',
        'submission_states': ['submitted', 'late'],
      });
      expect(a.status, 'submitted');
      expect(a.isLate, isTrue, reason: 'both chips must render');
      expect(a.states, containsAll(<String>['submitted', 'late']));
    });

    test('an unreleased mark is absent, not zero', () {
      final a = Assignment.fromJson(const {
        '_id': 'a3',
        'title': 'Marked, withheld',
        'type': 'quiz',
        'submission_status': 'graded',
        'submission': {
          '_id': 's3',
          'assignment_id': 'a3',
          'status': 'graded',
          'released': false,
          // `grade` and `feedback` are REMOVED by the backend in this state.
          'marking': null,
          'annotated_url': null,
        },
      });
      expect(a.isGraded, isTrue);
      expect(a.awaitingRelease, isTrue);
      expect(
        a.visibleGrade,
        isNull,
        reason: 'showing 0 here tells the student they failed',
      );
      expect(a.submission!.hasVisibleGrade, isFalse);
    });

    test('a released mark exposes grade, feedback and the breakdown', () {
      final a = Assignment.fromJson(const {
        '_id': 'a4',
        'title': 'Released',
        'type': 'homework',
        'submission_status': 'graded',
        'submission': {
          '_id': 's4',
          'assignment_id': 'a4',
          'status': 'graded',
          'released': true,
          'grade': 17,
          'feedback': 'Solid method.',
          'annotated_url': '/x.pdf',
          'marking': {
            'parts': [
              {'label': '1a', 'max': 5, 'awarded': 5, 'ok': true},
              {'label': '1b', 'max': 15, 'awarded': 12, 'ok': false},
            ],
            'total_awarded': 17,
            'total_max': 20,
            'percentage': 85,
            'strengths': ['Clear working'],
            'priorities': ['Units'],
            'target': 'Show units throughout',
            'exam': {'number': 'P1', 'session': 'May 2025', 'board': 'Edexcel'},
          },
        },
      });
      expect(a.awaitingRelease, isFalse);
      expect(a.visibleGrade, 17);
      expect(a.submission!.feedback, 'Solid method.');
      final m = a.submission!.marking!;
      expect(m.parts, hasLength(2));
      // Totals come from the server, which recomputes them from the parts.
      expect(m.totalAwarded, 17);
      expect(m.totalMax, 20);
      expect(m.exam!.board, 'Edexcel');
    });

    test('flattens the detail shape { assignment, submission }', () {
      final a = Assignment.fromJson(const {
        'assignment': {
          '_id': 'a5',
          'title': 'Detail shape',
          'type': 'homework',
          'class_name': 'Physics 12',
          'attachment_url': '/api/v1/student/assignments/a5/attachment',
          'attachment_filename': 'brief.pdf',
        },
        'submission': {
          '_id': 's5',
          'assignment_id': 'a5',
          'status': 'submitted',
          'released': false,
        },
      });
      expect(a.id, 'a5');
      expect(a.subjectName, 'Physics 12');
      expect(a.attachmentFilename, 'brief.pdf');
      expect(a.submission, isNotNull);
      expect(a.canResubmit, isTrue, reason: 'resubmit is open until graded');
    });

    test('resubmission closes once graded', () {
      final a = Assignment.fromJson(const {
        '_id': 'a6',
        'title': 'Done',
        'type': 'homework',
        'submission_status': 'graded',
      });
      expect(a.canResubmit, isFalse);
    });
  });

  group('ContentEmbed (API_BRIEF §6)', () {
    test('parses the provider and the Bunny watermark', () {
      final e = ContentEmbed.fromJson(const {
        'embed_url': 'https://iframe.mediadelivery.net/embed/1/x?token=t',
        'provider': 'bunny',
        'watermark': 'Sara Ali · +201200000000 · 65f0',
        'bunny_video_id': 'x',
      });
      expect(e.provider, VideoProvider.bunny);
      expect(e.provider.isSigned, isTrue);
      expect(e.watermark, isNotNull);
      expect(e.isStale, isFalse, reason: 'just fetched');
    });

    test('drive embeds are unsigned and never go stale', () {
      final e = ContentEmbed.fromJson(const {
        'embed_url': 'https://drive.google.com/file/d/abc/preview',
        'provider': 'drive',
      });
      expect(e.provider, VideoProvider.drive);
      expect(e.provider.isSigned, isFalse);
      expect(e.isStale, isFalse);
      // The backend sends no watermark for Drive — the client must build it.
      expect(e.watermark, isNull);
    });

    test('never leaks the embed url through toString', () {
      final e = ContentEmbed.fromJson(const {
        'embed_url': 'https://drive.google.com/file/d/SECRET/preview',
        'provider': 'drive',
      });
      expect(e.toString(), isNot(contains('SECRET')));
    });
  });

  group('Notifications (API_BRIEF §9)', () {
    test('page carries the authoritative unread_count', () {
      final p = NotificationsPage.fromJson(const {
        'notifications': [
          {'_id': 'n1', 'title': 'A', 'is_read': false},
          {'_id': 'n2', 'title': 'B', 'is_read': true},
        ],
        'unread_count': 7,
      });
      expect(p.items, hasLength(2));
      // Not recomputed from the page — the list is capped at 50 rows.
      expect(p.unreadCount, 7);
    });
  });

  group('SubjectsPage (API_BRIEF §5)', () {
    test('parses counts and echoed filters', () {
      final p = SubjectsPage.fromJson(const {
        'subjects': [
          {'_id': 's1', 'name': 'Physics', 'enrollment_status': 'active'},
        ],
        'filters': {'filter': 'enrolled', 'grade': 12, 'exam_board': 'Edexcel'},
        'counts': {'total': 9, 'enrolled': 1, 'pending': 2, 'available': 6},
      });
      expect(p.subjects, hasLength(1));
      expect(p.filter, 'enrolled');
      expect(p.grade, 12);
      expect(p.examBoard, 'Edexcel');
      expect(p.enrolled, 1);
      expect(p.available, 6);
    });
  });
}
