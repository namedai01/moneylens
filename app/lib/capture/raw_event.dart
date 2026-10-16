/// A VCB notification stored by the native listener in `capture.db`.
class RawEvent {
  final int id;
  final String packageName;
  final String? title;
  final String? text;
  final String? bigText;

  /// Notification post time, UTC.
  final DateTime postedAt;

  const RawEvent({
    required this.id,
    required this.packageName,
    required this.title,
    required this.text,
    required this.bigText,
    required this.postedAt,
  });

  /// Expanded text when the app provides it, otherwise the short text.
  String get body {
    final big = bigText;
    if (big != null && big.isNotEmpty) return big;
    return text ?? '';
  }

  factory RawEvent.fromRow(Map<String, Object?> r) => RawEvent(
    id: r['id']! as int,
    packageName: r['package_name']! as String,
    title: r['title'] as String?,
    text: r['text'] as String?,
    bigText: r['big_text'] as String?,
    postedAt: DateTime.fromMillisecondsSinceEpoch(
      r['posted_at']! as int,
      isUtc: true,
    ),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'packageName': packageName,
    'title': title,
    'text': text,
    'bigText': bigText,
    'postedAt': postedAt.millisecondsSinceEpoch,
  };
}
