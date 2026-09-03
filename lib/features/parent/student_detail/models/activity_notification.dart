import 'package:equatable/equatable.dart';

class ActivityNotification extends Equatable {
  const ActivityNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.createdAt,
    required this.read,
  });

  final String id;
  final String title;
  final String body;
  final String category; // assignment|grade|attendance|announcement|general
  final DateTime createdAt;
  final bool read;

  factory ActivityNotification.fromJson(Map<String, dynamic> j) =>
      ActivityNotification(
        id: (j['id'] ?? j['_id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        body: (j['body'] ?? '').toString(),
        category: (j['category'] ?? j['type'] ?? 'general').toString(),
        createdAt:
            DateTime.tryParse(j['created_at']?.toString() ?? '') ??
                DateTime.now(),
        read: j['read'] == true,
      );

  @override
  List<Object?> get props => [id, title, body, category, createdAt, read];
}
