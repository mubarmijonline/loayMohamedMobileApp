import 'package:equatable/equatable.dart';

/// A student linked to a parent account (summary, not full student profile).
class LinkedStudent extends Equatable {
  const LinkedStudent({
    required this.id,
    required this.name,
    this.grade,
    this.avatarUrl,
  });

  final String id;
  final String name;
  final String? grade;
  final String? avatarUrl;

  factory LinkedStudent.fromJson(Map<String, dynamic> json) => LinkedStudent(
        id: (json['_id'] ?? json['id'] ?? '').toString(),
        name: (json['name'] ?? json['full_name'] ?? '').toString(),
        grade: json['grade']?.toString(),
        avatarUrl: (json['avatar_url'] ?? json['avatar'])?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'grade': grade,
        'avatar_url': avatarUrl,
      };

  @override
  List<Object?> get props => [id, name, grade, avatarUrl];
}

class StudentUser extends Equatable {
  const StudentUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.phone,
    this.parentPhone,
    this.school,
    this.avatarUrl,
    this.grade,
    this.linkedStudents = const [],
  });

  final String id;
  final String name;
  final String email;
  final String role; // expected: 'student'
  final String? phone;
  final String? parentPhone;
  final String? school;
  final String? avatarUrl;
  final String? grade;
  /// Populated for parent accounts — list of students linked to this parent.
  final List<LinkedStudent> linkedStudents;

  bool get isStudent => role.toLowerCase() == 'student';
  bool get isParent => role.toLowerCase() == 'parent';

  /// True if the email is an Apple "Hide My Email" relay address. Such users
  /// are forced through the Complete-Profile screen so they can enter a real
  /// reachable address.
  bool get hasApplePrivateRelayEmail =>
      email.toLowerCase().endsWith('@privaterelay.appleid.com');

  /// Returns true when one or more of the fields required to actually use the
  /// app (mobile, parent mobile, school, grade) is missing. Used to gate the
  /// app behind the "Complete your profile" screen for users who came in via
  /// Apple/Google sign-in (those flows usually only have name + email).
  bool get isProfileComplete {
    bool _has(String? v) => (v ?? '').trim().isNotEmpty;
    return _has(phone) &&
        _has(parentPhone) &&
        _has(school) &&
        _has(grade) &&
        !hasApplePrivateRelayEmail;
  }

  factory StudentUser.fromJson(Map<String, dynamic> json) {
    return StudentUser(
      id: (json['_id'] ?? json['id'] ?? json['student_id'] ?? '').toString(),
      name: (json['name'] ?? json['full_name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      role: (json['role'] ?? 'student').toString(),
      phone: (json['phone'] ?? json['mobile'])?.toString(),
      parentPhone: (json['parent_phone'] ?? json['guardian_phone'] ?? json['parent_mobile'])?.toString(),
      school: (json['school'] ?? json['school_name'])?.toString(),
      avatarUrl: (json['avatar_url'] ??
              json['avatar'] ??
              json['profile_image'] ??
              json['profile_image_url'] ??
              json['photo_url'] ??
              json['image'] ??
              json['picture'])
          ?.toString(),
      grade: json['grade']?.toString(),
      linkedStudents: (json['linked_students'] as List<dynamic>? ?? [])
          .map((e) => LinkedStudent.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role,
        'phone': phone,
        'parent_phone': parentPhone,
        'school': school,
        'avatar_url': avatarUrl,
        'grade': grade,
        'linked_students': linkedStudents.map((s) => s.toJson()).toList(),
      };

  StudentUser copyWith({
    String? phone,
    String? parentPhone,
    String? school,
    String? name,
    String? avatarUrl,
    String? grade,
    List<LinkedStudent>? linkedStudents,
  }) => StudentUser(
        id: id,
        name: name ?? this.name,
        email: email,
        role: role,
        phone: phone ?? this.phone,
        parentPhone: parentPhone ?? this.parentPhone,
        school: school ?? this.school,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        grade: grade ?? this.grade,
        linkedStudents: linkedStudents ?? this.linkedStudents,
      );

  @override
  List<Object?> get props => [id, name, email, role, phone, parentPhone, school, avatarUrl, grade, linkedStudents];
}
