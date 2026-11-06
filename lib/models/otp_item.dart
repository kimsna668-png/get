class OtpItem {
  final String code;
  final String sender;
  final String subject;
  final String accountEmail;
  final DateTime receivedAt;
  final String fingerprint;

  const OtpItem({
    required this.code,
    required this.sender,
    required this.subject,
    required this.accountEmail,
    required this.receivedAt,
    required this.fingerprint,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'sender': sender,
        'subject': subject,
        'accountEmail': accountEmail,
        'receivedAt': receivedAt.toIso8601String(),
        'fingerprint': fingerprint,
      };

  factory OtpItem.fromJson(Map<String, dynamic> json) => OtpItem(
        code: json['code'] as String,
        sender: json['sender'] as String? ?? 'Unknown sender',
        subject: json['subject'] as String? ?? '(No subject)',
        accountEmail: json['accountEmail'] as String,
        receivedAt: DateTime.tryParse(json['receivedAt'] as String? ?? '') ?? DateTime.now(),
        fingerprint: json['fingerprint'] as String,
      );
}
