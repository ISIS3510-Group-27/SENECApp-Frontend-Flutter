import 'package:flutter/foundation.dart';

/// What an event's QR code says: `senecapp://check-in?event_id=12&code=AB3X9K`.
@immutable
class CheckInPayload {
  const CheckInPayload({required this.eventId, required this.code});

  /// Reads a scanned QR code, or returns `null` if it isn't a SENECApp
  /// check-in code (a URL, a Wi-Fi code...).
  static CheckInPayload? tryParse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'senecapp' || uri.host != 'check-in') {
      return null;
    }
    final eventId = int.tryParse(uri.queryParameters['event_id'] ?? '');
    final code = uri.queryParameters['code'];
    if (eventId == null || code == null || code.isEmpty) return null;
    return CheckInPayload(eventId: eventId, code: code);
  }

  final int eventId;
  final String code;
}

/// The QR code an organizer shows at the venue (`GET
/// /events/{id}/check-in-code`, group admins only).
@immutable
class CheckInCode {
  const CheckInCode({required this.code, required this.qrPayload});

  factory CheckInCode.fromJson(Map<String, dynamic> json) => CheckInCode(
    code: json['code'] as String,
    qrPayload: json['qr_payload'] as String,
  );

  /// Also shown as text, for attendees whose camera won't cooperate.
  final String code;

  /// What goes in the QR code.
  final String qrPayload;
}

/// The backend's answer to a check-in.
@immutable
class CheckInResult {
  const CheckInResult({
    required this.checkedInAt,
    required this.alreadyCheckedIn,
    this.distanceM,
  });

  factory CheckInResult.fromJson(Map<String, dynamic> json) => CheckInResult(
    checkedInAt: DateTime.parse(json['checked_in_at'] as String),
    alreadyCheckedIn: json['already_checked_in'] as bool,
    distanceM: (json['distance_m'] as num?)?.toDouble(),
  );

  final DateTime checkedInAt;

  /// Scanning twice is fine: the second time just says so.
  final bool alreadyCheckedIn;

  /// How far from the venue the phone was, when its location was sent.
  final double? distanceM;
}
