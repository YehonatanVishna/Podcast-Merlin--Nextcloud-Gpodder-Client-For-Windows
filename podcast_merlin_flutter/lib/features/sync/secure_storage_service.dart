import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SecureStorageService {
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String keyServerUrl = 'nextcloud_server_url';
  static const String keyUsername = 'nextcloud_username';
  static const String keyPassword = 'nextcloud_password';
  static const String keyDeviceId = 'gpodder_device_id';
  static const String keyLastActionTimestamp = 'last_action_timestamp';
  static const String keyPodcastIndexApiKey = 'podcast_index_api_key';
  static const String keyPodcastIndexApiSecret = 'podcast_index_api_secret';

  Future<void> write(String key, String value) async {
    try {
      await _secureStorage.write(key: key, value: value);
    } catch (e) {
      if (kDebugMode) print('SecureStorage write error, using fallback: $e');
    }
    await _writeFallback(key, value);
  }

  Future<String?> read(String key) async {
    try {
      final value = await _secureStorage.read(key: key);
      if (value != null && value.isNotEmpty) {
        return value;
      }
    } catch (e) {
      if (kDebugMode) print('SecureStorage read error, checking fallback: $e');
    }
    return await _readFallback(key);
  }

  Future<void> delete(String key) async {
    try {
      await _secureStorage.delete(key: key);
    } catch (_) {}
    await _deleteFallback(key);
  }

  // --- FALLBACK FILE & MEMORY STORAGE ---
  static final Map<String, String> _memoryFallback = {};

  Future<File?> get _fallbackFile async {
    if (kIsWeb) return null;
    try {
      final appDir = await getApplicationSupportDirectory();
      final file = File(p.join(appDir.path, '.merlin_auth_store'));
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      return file;
    } catch (e) {
      if (kDebugMode) print('PathProvider error in SecureStorage fallback: $e');
      return null;
    }
  }

  Future<void> _writeFallback(String key, String value) async {
    _memoryFallback[key] = value;
    try {
      final file = await _fallbackFile;
      if (file == null) return;
      Map<String, dynamic> data = {};
      if (await file.length() > 0) {
        final content = await file.readAsString();
        data = jsonDecode(content) as Map<String, dynamic>;
      }
      data[key] = value;
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      if (kDebugMode) print('Fallback write file error: $e');
    }
  }

  Future<String?> _readFallback(String key) async {
    try {
      final file = await _fallbackFile;
      if (file != null && await file.exists() && await file.length() > 0) {
        final content = await file.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        final val = data[key] as String?;
        if (val != null && val.isNotEmpty) return val;
      }
    } catch (e) {
      if (kDebugMode) print('Fallback read file error: $e');
    }
    return _memoryFallback[key];
  }

  Future<void> _deleteFallback(String key) async {
    _memoryFallback.remove(key);
    try {
      final file = await _fallbackFile;
      if (file != null && await file.exists() && await file.length() > 0) {
        final content = await file.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        data.remove(key);
        await file.writeAsString(jsonEncode(data));
      }
    } catch (_) {}
  }
}
