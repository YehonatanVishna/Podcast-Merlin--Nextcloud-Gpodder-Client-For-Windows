import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/features/sync/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureStorageService Unit Tests', () {
    late SecureStorageService storage;

    setUp(() {
      storage = SecureStorageService();
    });

    test('write and read credentials via storage service', () async {
      await storage.write(SecureStorageService.keyServerUrl, 'https://nextcloud.example.com');
      await storage.write(SecureStorageService.keyUsername, 'testuser');
      await storage.write(SecureStorageService.keyPassword, 'secretpass');

      final serverUrl = await storage.read(SecureStorageService.keyServerUrl);
      final username = await storage.read(SecureStorageService.keyUsername);
      final password = await storage.read(SecureStorageService.keyPassword);

      expect(serverUrl, 'https://nextcloud.example.com');
      expect(username, 'testuser');
      expect(password, 'secretpass');
    });

    test('delete credential key clears value from storage service', () async {
      await storage.write(SecureStorageService.keyUsername, 'deleteuser');
      expect(await storage.read(SecureStorageService.keyUsername), 'deleteuser');

      await storage.delete(SecureStorageService.keyUsername);
      expect(await storage.read(SecureStorageService.keyUsername), isNull);
    });
  });
}
