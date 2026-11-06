# KSM OTP Receiver (Flutter / Android)

Private OTP inbox reader for Yandex Mail and Zoho Mail accounts that you own or are authorized to access.

## Features in this starter release

- Add multiple Yandex / Zoho mailboxes using IMAP over SSL/TLS (port 993).
- Test credentials before saving.
- Store app passwords with `flutter_secure_storage` on Android.
- Check the 30 most recent Inbox messages on demand / pull-to-refresh.
- Android background checks using WorkManager (minimum 15-minute interval; actual execution is system-controlled).
- Local notifications for newly detected OTPs.
- Detect likely 4–8 digit OTPs near verification keywords.
- Display and copy OTPs; keep a local history (up to 100).
- Uses `BODY.PEEK[]` so it does not intentionally mark messages as read.

## Important limitations

- Background checks use Android WorkManager. The minimum periodic interval is 15 minutes and Android decides the actual run time based on battery, network, Doze and vendor power management. It is not real-time push and cannot guarantee an exact interval. Force-stopping the app can stop scheduled work until the user opens it again.
- It reads Inbox only, not Spam, Trash, or arbitrary folders.
- OTP parsing is heuristic. It may miss unusual email templates or match a code that is not an OTP. Review the sender and subject before using a code.
- Email message dates are not currently decoded by the starter; detected entries are timestamped when checked.
- This version does not use Yandex/Zoho OAuth. It uses provider-issued app-specific passwords over IMAP.
- Never enter your normal account password if the provider supports app passwords.

## Provider setup

### Yandex Mail

1. Open Yandex Mail settings and go to Email clients.
2. Enable IMAP access for `imap.yandex.com` and enable App passwords / OAuth tokens.
3. In Yandex ID, create an app password for Mail.
4. In the app, add Yandex and use:
   - Host: `imap.yandex.com`
   - Port: `993` (SSL/TLS)
   - Username: your full email address
   - Password: the app password

If your account is in a region that uses another Yandex host, use the host shown in your Yandex settings.

### Zoho Mail

1. In Zoho Mail Settings → Mail Accounts → your account, enable IMAP Access.
2. If MFA/2FA is enabled, create an application-specific password in Zoho Accounts.
3. Add Zoho in the app:
   - Personal mailbox default: `imap.zoho.com`
   - Port: `993` (SSL/TLS)
   - Username: full email address
   - Password: app-specific password
4. For paid organization/domain accounts, Zoho may use `imappro.zoho.com` or another datacenter-specific server. Use the exact server listed in your Zoho account settings.

## Build APK

Install Flutter SDK and Android Studio / Android SDK first. Then from this project folder:

```bash
flutter doctor
flutter pub get
flutter analyze
flutter run
```

Build a release APK:

```bash
flutter build apk --release
```

Output:
`build/app/outputs/flutter-apk/app-release.apk`

Build a smaller APK per CPU architecture (optional):

```bash
flutter build apk --release --split-per-abi
```

For Play Store distribution, configure your own Android signing key and `key.properties`. Do not commit signing keys or passwords to source control.

## Project structure

```text
ksm_otp_receiver/
├── android/
│   └── app/src/main/AndroidManifest.xml
├── lib/
│   ├── main.dart
│   ├── models/
│   │   ├── mail_account.dart
│   │   └── otp_item.dart
│   └── services/
│       ├── account_store.dart
│       └── imap_service.dart
├── analysis_options.yaml
├── pubspec.yaml
└── README.md
```

## Security notes

- Use only mailboxes you own or are explicitly authorized to access.
- App passwords can usually be revoked independently in provider security settings.
- The app does not send email or change mailbox settings.
- OTP history is stored locally in app preferences. Remove the account and clear history before handing your phone to another person.
- Do not share your APK with embedded credentials. Credentials are entered by the user at runtime.

## Background monitoring

1. Open the app and connect one or more mailboxes.
2. Grant notification permission when Android asks.
3. Turn on **Background OTP Monitoring** from the dashboard.
4. Android WorkManager checks periodically, with a 15-minute minimum interval. The OS may delay runs. Open the app to refresh immediately.
5. Disable the switch to cancel periodic checks.

For Android 13+, notifications require runtime permission. Some phone manufacturers also require allowing background activity / disabling battery optimization for this app. Do not force-stop the app if you want scheduled checks to continue.
