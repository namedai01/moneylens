/// A notification posted by another app, as seen by the listener.
class CapturedNotification {
  final String packageName;
  final String? title;
  final String? text;
  final String? bigText;
  final DateTime postedAt;

  const CapturedNotification({
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

  Map<String, dynamic> toJson() => {
    'packageName': packageName,
    'title': title,
    'text': text,
    'bigText': bigText,
    'postedAt': postedAt.millisecondsSinceEpoch,
  };

  factory CapturedNotification.fromJson(Map<String, dynamic> json) =>
      CapturedNotification(
        packageName: json['packageName'] as String,
        title: json['title'] as String?,
        text: json['text'] as String?,
        bigText: json['bigText'] as String?,
        postedAt: DateTime.fromMillisecondsSinceEpoch(
          json['postedAt'] as int,
          isUtc: true,
        ),
      );
}

/// True for Vietcombank apps (exact package id is confirmed during the spike).
bool isVcbPackage(String packageName) {
  final p = packageName.toLowerCase();
  return p.contains('vcb') || p.contains('vietcombank');
}
