class TikNetNotification {
  TikNetNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.read,
    this.createdAt,
  });

  final int id;
  final String title;
  final String body;
  final String type;
  final bool read;
  final DateTime? createdAt;

  factory TikNetNotification.fromJson(Map<String, dynamic> json) {
    final createdStr = json['created_at'] as String?;
    return TikNetNotification(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      type: (json['type'] as String?) ?? 'info',
      read: json['read'] as bool? ?? false,
      createdAt: createdStr != null ? DateTime.tryParse(createdStr) : null,
    );
  }
}

class TikNetInbox {
  TikNetInbox({required this.notifications, required this.unreadCount});

  final List<TikNetNotification> notifications;
  final int unreadCount;

  factory TikNetInbox.fromJson(Map<String, dynamic> json) {
    final raw = json['notifications'];
    final items = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => TikNetNotification.fromJson(Map<String, dynamic>.from(e)))
            .where((n) => n.id > 0 && n.title.isNotEmpty)
            .toList()
        : <TikNetNotification>[];
    return TikNetInbox(
      notifications: items,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? items.where((n) => !n.read).length,
    );
  }

  static const empty = TikNetInbox(notifications: [], unreadCount: 0);
}
