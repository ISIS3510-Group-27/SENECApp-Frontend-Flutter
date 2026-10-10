import 'package:flutter/foundation.dart';

/// A member asking to become an admin of a group (`/groups/{id}/admin-requests`).
@immutable
class AdminRequest {
  const AdminRequest({
    required this.id,
    required this.requesterName,
    required this.requesterEmail,
    required this.createdAt,
    this.note,
  });

  factory AdminRequest.fromJson(Map<String, dynamic> json) {
    final requester = json['requester'] as Map<String, dynamic>;
    return AdminRequest(
      id: json['id'] as int,
      requesterName: requester['full_name'] as String,
      requesterEmail: requester['email'] as String,
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final int id;
  final String requesterName;
  final String requesterEmail;
  final String? note;
  final DateTime createdAt;
}
