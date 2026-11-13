import '../../../core/database/browser_storage.dart';
import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

class AuthStore {
  Stream<void> get sessionChanges {
    late StreamController<void> controller;
    final listener = ((web.Event event) {
      final key = (event as web.StorageEvent).key;
      if (key == null || key == 'diexu.cloudbase.auth.session.v1') {
        controller.add(null);
      }
    }).toJS;
    controller = StreamController<void>(
      onListen: () => web.window.addEventListener('storage', listener),
      onCancel: () => web.window.removeEventListener('storage', listener),
    );
    return controller.stream;
  }

  Future<String?> read(String key) async => browserStorage[key];

  Future<void> write(String key, String value) async {
    browserStorage[key] = value;
  }

  Future<void> delete(String key) async {
    browserStorage.remove(key);
  }
}
