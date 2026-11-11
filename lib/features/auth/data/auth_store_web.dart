import '../../../core/database/browser_storage.dart';

class AuthStore {
  Future<String?> read(String key) async => browserStorage[key];

  Future<void> write(String key, String value) async {
    browserStorage[key] = value;
  }

  Future<void> delete(String key) async {
    browserStorage.remove(key);
  }
}
