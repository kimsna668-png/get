import 'package:enough_mail/enough_mail.dart';

import '../models/mail_account.dart';
import '../models/otp_item.dart';

class ImapService {
  // Keep detection conservative: a number must appear near OTP/verification language.
  static final RegExp _otpRegex = RegExp(
    r'(?:otp|one[\s-]?time|verification|verify|security|confirmation|passcode|code)[^\d]{0,45}(\d{4,8})',
    caseSensitive: false,
  );
  static final RegExp _reverseOtpRegex = RegExp(
    r'(\d{4,8})[^\w]{0,25}(?:is your|is the|as your)?\s*(?:otp|verification code|security code|passcode)',
    caseSensitive: false,
  );

  Future<void> checkConnection(MailAccount account, String password) async {
    final client = ImapClient(isLogEnabled: false);
    try {
      await client.connectToServer(account.host, account.port, isSecure: true);
      await client.login(account.email, password);
      await client.selectInbox();
    } finally {
      try {
        await client.logout();
      } catch (_) {
        // Ignore logout errors after a successful/failed test connection.
      }
    }
  }

  Future<List<OtpItem>> fetchOtps(MailAccount account, String password) async {
    final client = ImapClient(isLogEnabled: false);
    final found = <OtpItem>[];
    try {
      await client.connectToServer(account.host, account.port, isSecure: true);
      await client.login(account.email, password);
      await client.selectInbox();

      // Read only a limited number of recent messages; BODY.PEEK avoids marking as read.
      final result = await client.fetchRecentMessages(
        messageCount: 30,
        criteria: 'BODY.PEEK[]',
      );

      for (final dynamic message in result.messages) {
        final subject = _safe(() => message.decodeSubject()) ?? '(No subject)';
        final body = _safe(() => message.decodeTextPlainPart()) ?? '';
        final html = _safe(() => message.decodeTextHtmlPart()) ?? '';
        final content = '$subject\n$body\n$html';
        final match = _otpRegex.firstMatch(content) ?? _reverseOtpRegex.firstMatch(content);
        if (match == null) continue;

        final code = match.group(1);
        if (code == null) continue;

        final sender = _safe(() => message.from.toString()) ?? 'Unknown sender';
        final received = DateTime.now();
        final fingerprint = '${account.email}|$sender|$subject|$code|${content.hashCode}';

        found.add(OtpItem(
          code: code,
          sender: sender,
          subject: subject,
          accountEmail: account.email,
          receivedAt: received,
          fingerprint: fingerprint,
        ));
      }
    } finally {
      try {
        await client.logout();
      } catch (_) {}
    }
    return found;
  }

  String? _safe(String? Function() read) {
    try {
      return read();
    } catch (_) {
      return null;
    }
  }
}
