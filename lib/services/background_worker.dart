import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import '../models/otp_item.dart';
import 'account_store.dart';
import 'imap_service.dart';

const String otpBackgroundTask = 'ksmOtpBackgroundCheck';
const String otpBackgroundUniqueName = 'ksm_otp_periodic_monitor';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    if (task != otpBackgroundTask) return true;

    final store = AccountStore();
    final imap = ImapService();
    final notifications = FlutterLocalNotificationsPlugin();

    await notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    final accounts = await store.loadAccounts();
    final history = await store.loadOtps();
    final knownFingerprints = history.map((e) => e.fingerprint).toSet();
    final newlyFound = <OtpItem>[];

    for (final account in accounts) {
      try {
        final password = await store.readPassword(account.id);
        if (password == null || password.isEmpty) continue;
        final items = await imap.fetchOtps(account, password);
        for (final item in items) {
          if (knownFingerprints.add(item.fingerprint)) {
            newlyFound.add(item);
          }
        }
      } catch (_) {
        // WorkManager retries only when the task returns false.
        // One mailbox failing should not block the remaining accounts.
      }
    }

    if (newlyFound.isNotEmpty) {
      history.insertAll(0, newlyFound);
      history.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
      final trimmed = history.take(100).toList();
      await store.saveOtps(trimmed);

      for (final item in newlyFound.take(5)) {
        await notifications.show(
          item.fingerprint.hashCode & 0x7fffffff,
          'New OTP received',
          '${item.code} • ${item.accountEmail}',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'ksm_otp_alerts',
              'OTP Alerts',
              channelDescription: 'Alerts when a new email verification code is detected.',
              importance: Importance.max,
              priority: Priority.high,
              ticker: 'New OTP',
            ),
          ),
          payload: item.code,
        );
      }
    }

    return true;
  });
}
