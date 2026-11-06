import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:workmanager/workmanager.dart';

import 'models/mail_account.dart';
import 'models/otp_item.dart';
import 'services/account_store.dart';
import 'services/imap_service.dart';
import 'services/background_monitor.dart';
import 'services/background_worker.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(callbackDispatcher);
  await NotificationService().initializeAndRequestPermission();
  runApp(const KsmOtpApp());
}

class KsmOtpApp extends StatelessWidget {
  const KsmOtpApp({super.key});

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD6AD60);
    return MaterialApp(
      title: 'KSM OTP Receiver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0D12),
        colorScheme: const ColorScheme.dark(
          primary: gold,
          secondary: gold,
          surface: Color(0xFF171B24),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B0D12),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF10141C),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF303746)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF303746)),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _store = AccountStore();
  final _imap = ImapService();
  final _background = BackgroundMonitor();
  bool _backgroundEnabled = false;
  List<MailAccount> _accounts = [];
  List<OtpItem> _otps = [];
  bool _loading = true;
  bool _checking = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accounts = await _store.loadAccounts();
    final backgroundEnabled = await _background.isEnabled();
    final otps = await _store.loadOtps();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _otps = otps;
      _backgroundEnabled = backgroundEnabled;
      _loading = false;
    });
  }


  Future<void> _toggleBackground() async {
    if (_accounts.isEmpty) {
      _message('Add an email account before enabling background monitoring.');
      return;
    }
    try {
      if (_backgroundEnabled) {
        await _background.disable();
      } else {
        await _background.enable();
      }
      if (!mounted) return;
      setState(() => _backgroundEnabled = !_backgroundEnabled);
      _message(_backgroundEnabled
          ? 'Background monitoring enabled (Android may run it later, typically every 15+ minutes).'
          : 'Background monitoring disabled.');
    } catch (e) {
      _message('Could not update background monitoring: ${_friendlyError(e)}');
    }
  }

  Future<void> _addAccount() async {
    final result = await showDialog<NewAccountData>(
      context: context,
      builder: (_) => const AddAccountDialog(),
    );
    if (result == null) return;

    try {
      final account = MailAccount(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        provider: result.provider,
        email: result.email.trim(),
        host: result.host.trim(),
        port: 993,
      );
      await _imap.checkConnection(account, result.password);
      await _store.savePassword(account.id, result.password);
      await _store.addAccount(account);
      await _load();
      _message('Account connected successfully.');
      await _refresh();
    } catch (e) {
      _message('Connection failed: ${_friendlyError(e)}');
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.length > 180) return '${s.substring(0, 180)}…';
    return s;
  }

  Future<void> _removeAccount(MailAccount account) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove account?'),
        content: Text('Remove ${account.email} and its saved app password?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await _store.removeAccount(account.id);
    await _load();
  }

  Future<void> _refresh() async {
    if (_checking || _accounts.isEmpty) return;
    setState(() {
      _checking = true;
      _status = 'Checking connected mailboxes…';
    });

    int found = 0;
    final errors = <String>[];
    for (final account in _accounts) {
      try {
        final password = await _store.readPassword(account.id);
        if (password == null || password.isEmpty) {
          errors.add('${account.email}: missing saved password');
          continue;
        }
        final items = await _imap.fetchOtps(account, password);
        for (final item in items) {
          final exists = _otps.any((old) => old.fingerprint == item.fingerprint);
          if (!exists) {
            _otps.insert(0, item);
            found++;
          }
        }
      } catch (e) {
        errors.add('${account.email}: ${_friendlyError(e)}');
      }
    }
    _otps.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    if (_otps.length > 100) _otps = _otps.take(100).toList();
    await _store.saveOtps(_otps);

    if (!mounted) return;
    setState(() {
      _checking = false;
      _status = errors.isEmpty
          ? (found == 0 ? 'No new OTP found.' : '$found new OTP(s) received.')
          : 'Finished with ${errors.length} account error(s).';
    });
    if (errors.isNotEmpty) _message(errors.join('\n'));
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    _message('OTP copied.');
  }

  Future<void> _clearHistory() async {
    await _store.clearOtps();
    if (!mounted) return;
    setState(() => _otps.clear());
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final latest = _otps.isEmpty ? null : _otps.first;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.shield_moon_outlined, color: Color(0xFFD6AD60)),
            SizedBox(width: 10),
            Text('KSM OTP Receiver', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh mailboxes',
            onPressed: _checking ? null : _refresh,
            icon: _checking
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addAccount,
        backgroundColor: const Color(0xFFD6AD60),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Add Email'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  _heroCard(),
                  const SizedBox(height: 12),
                  Card(
                    child: SwitchListTile(
                      value: _backgroundEnabled,
                      onChanged: (_) => _toggleBackground(),
                      activeColor: const Color(0xFFD6AD60),
                      secondary: const Icon(Icons.notifications_active_outlined, color: Color(0xFFD6AD60)),
                      title: const Text('Background OTP Monitoring', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        _backgroundEnabled
                            ? 'Enabled • checks when Android schedules it (15+ min minimum)'
                            : 'Off • enable to check while the app is closed',
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _sectionTitle('LATEST OTP', trailing: '${_otps.length} saved'),
                  if (latest == null)
                    _emptyCard('No OTP received yet', 'Connect an email account and tap refresh.')
                  else
                    _otpCard(latest, prominent: true),
                  const SizedBox(height: 20),
                  _sectionTitle('CONNECTED EMAILS', trailing: '${_accounts.length} account(s)'),
                  if (_accounts.isEmpty)
                    _emptyCard('No email accounts', 'Add your own Yandex or Zoho mailbox to begin.')
                  else
                    ..._accounts.map(_accountCard),
                  const SizedBox(height: 20),
                  _sectionTitle(
                    'OTP HISTORY',
                    trailing: TextButton(
                      onPressed: _otps.isEmpty ? null : _clearHistory,
                      child: const Text('Clear'),
                    ),
                  ),
                  if (_otps.isEmpty)
                    _emptyCard('History is empty', 'Detected codes will appear here.')
                  else
                    ..._otps.skip(1).map((item) => _otpCard(item)),
                  if (_status != null) ...[
                    const SizedBox(height: 16),
                    Text(_status!, style: const TextStyle(color: Color(0xFFD6AD60))),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    'Privacy: OTPs are read from mailboxes you connect. Use app-specific passwords and remove accounts you no longer use.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _heroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF292318), Color(0xFF171B24)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFF6C5732)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('YOUR MAILBOX OTP HUB', style: TextStyle(color: Color(0xFFD6AD60), fontSize: 11, letterSpacing: 1.4)),
                SizedBox(height: 8),
                Text('One place. Your codes.', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                SizedBox(height: 5),
                Text('Private IMAP inbox checking', style: TextStyle(color: Colors.white60)),
              ],
            ),
          ),
          const Icon(Icons.verified_user_outlined, size: 44, color: Color(0xFFD6AD60)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.white70)),
            const Spacer(),
            if (trailing != null) trailing,
          ],
        ),
      );

  Widget _emptyCard(String title, String subtitle) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              const Icon(Icons.mark_email_unread_outlined, color: Colors.white38, size: 30),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
      );

  Widget _accountCard(MailAccount account) => Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF292318),
            child: Text(account.provider == 'Yandex' ? 'Y' : 'Z', style: const TextStyle(color: Color(0xFFD6AD60), fontWeight: FontWeight.bold)),
          ),
          title: Text(account.email, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${account.provider} • ${account.host}:993', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          trailing: IconButton(
            tooltip: 'Remove account',
            onPressed: () => _removeAccount(account),
            icon: const Icon(Icons.delete_outline, color: Colors.white54),
          ),
        ),
      );

  Widget _otpCard(OtpItem item, {bool prominent = false}) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(item.code, style: TextStyle(fontSize: prominent ? 34 : 26, fontWeight: FontWeight.w800, letterSpacing: 5, color: const Color(0xFFD6AD60)))),
                  IconButton(
                    tooltip: 'Copy OTP',
                    onPressed: () => _copy(item.code),
                    icon: const Icon(Icons.copy, color: Color(0xFFD6AD60)),
                  ),
                ],
              ),
              Text(item.sender, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              const SizedBox(height: 3),
              Text(item.subject, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text(item.accountEmail, style: const TextStyle(fontSize: 11, color: Colors.white38))),
                  Text(DateFormat('MMM d, HH:mm').format(item.receivedAt.toLocal()), style: const TextStyle(fontSize: 11, color: Colors.white38)),
                ],
              ),
            ],
          ),
        ),
      );
}

class NewAccountData {
  final String provider;
  final String email;
  final String password;
  final String host;
  const NewAccountData(this.provider, this.email, this.password, this.host);
}

class AddAccountDialog extends StatefulWidget {
  const AddAccountDialog({super.key});

  @override
  State<AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<AddAccountDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _host = TextEditingController(text: 'imap.yandex.com');
  String _provider = 'Yandex';
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _host.dispose();
    super.dispose();
  }

  void _providerChanged(String? value) {
    if (value == null) return;
    setState(() {
      _provider = value;
      _host.text = value == 'Yandex' ? 'imap.yandex.com' : 'imap.zoho.com';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect mailbox'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _provider,
              decoration: const InputDecoration(labelText: 'Email provider'),
              items: const [
                DropdownMenuItem(value: 'Yandex', child: Text('Yandex Mail')),
                DropdownMenuItem(value: 'Zoho', child: Text('Zoho Mail')),
              ],
              onChanged: _providerChanged,
            ),
            const SizedBox(height: 12),
            TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Full email address')),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'App-specific password',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: _host, decoration: const InputDecoration(labelText: 'IMAP server')),
            const SizedBox(height: 8),
            const Text('SSL/TLS port 993 is used. For Zoho organization accounts, use the IMAP server shown in your Zoho account settings.', style: TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final email = _email.text.trim();
            final password = _password.text.trim();
            final host = _host.text.trim();
            if (!email.contains('@') || password.isEmpty || host.isEmpty) return;
            Navigator.pop(context, NewAccountData(_provider, email, password, host));
          },
          child: const Text('Test & Connect'),
        ),
      ],
    );
  }
}
