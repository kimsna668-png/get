import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mail_account.dart';
import '../models/otp_item.dart';

class AccountStore {
  static const _accountsKey = 'ksm_accounts_v1';
  static const _otpsKey = 'ksm_otp_history_v1';
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<List<MailAccount>> loadAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_accountsKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => MailAccount.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addAccount(MailAccount account) async {
    final accounts = await loadAccounts();
    accounts.removeWhere((a) => a.id == account.id || a.email.toLowerCase() == account.email.toLowerCase());
    accounts.add(account);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountsKey, jsonEncode(accounts.map((a) => a.toJson()).toList()));
  }

  Future<void> removeAccount(String id) async {
    final accounts = await loadAccounts();
    accounts.removeWhere((a) => a.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountsKey, jsonEncode(accounts.map((a) => a.toJson()).toList()));
    await _secure.delete(key: _passwordKey(id));
  }

  String _passwordKey(String id) => 'mail_password_$id';

  Future<void> savePassword(String id, String password) =>
      _secure.write(key: _passwordKey(id), value: password);

  Future<String?> readPassword(String id) =>
      _secure.read(key: _passwordKey(id));

  Future<List<OtpItem>> loadOtps() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_otpsKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => OtpItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveOtps(List<OtpItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_otpsKey, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  Future<void> clearOtps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_otpsKey);
  }
}
