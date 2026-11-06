class MailAccount {
  final String id;
  final String provider;
  final String email;
  final String host;
  final int port;

  const MailAccount({
    required this.id,
    required this.provider,
    required this.email,
    required this.host,
    this.port = 993,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'provider': provider,
        'email': email,
        'host': host,
        'port': port,
      };

  factory MailAccount.fromJson(Map<String, dynamic> json) => MailAccount(
        id: json['id'] as String,
        provider: json['provider'] as String,
        email: json['email'] as String,
        host: json['host'] as String,
        port: (json['port'] as num?)?.toInt() ?? 993,
      );
}
