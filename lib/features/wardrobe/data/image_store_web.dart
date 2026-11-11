import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

/// IndexedDB stores image bytes independently from metadata and its quota.
class ImageStore {
  const ImageStore();
  static Future<web.IDBDatabase>? _opening;
  Future<web.IDBDatabase> get _db => _opening ??= _open();

  Future<web.IDBDatabase> _open() {
    final done = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open('diexu_media', 1);
    request.onupgradeneeded = ((web.Event _) {
      (request.result as web.IDBDatabase).createObjectStore('images');
    }).toJS;
    request.onsuccess = ((web.Event _) => done.complete(
      request.result as web.IDBDatabase,
    )).toJS;
    request.onerror = ((web.Event _) {
      _opening = null;
      done.completeError(StateError('无法打开图片存储'));
    }).toJS;
    return done.future;
  }

  Future<void> _complete(web.IDBTransaction txn) {
    final done = Completer<void>();
    txn.oncomplete = ((web.Event _) => done.complete()).toJS;
    void failed(web.Event _) {
      if (!done.isCompleted) done.completeError(StateError('图片存储失败，可能空间不足'));
    }

    txn.onabort = failed.toJS;
    txn.onerror = failed.toJS;
    return done.future;
  }

  Future<String> persist(XFile image) async =>
      persistBytes(await image.readAsBytes());
  Future<String> persistBytes(Uint8List bytes) async {
    final id = const Uuid().v4();
    final txn = (await _db).transaction('images'.toJS, 'readwrite');
    final done = _complete(txn);
    txn.objectStore('images').put(bytes.toJS, id.toJS);
    await done;
    return 'local-image:$id';
  }

  Future<Uint8List> readBytes(String path) async {
    if (path.startsWith('data:')) return UriData.parse(path).contentAsBytes();
    if (!path.startsWith('local-image:')) throw StateError('图片不在当前设备');
    final txn = (await _db).transaction('images'.toJS, 'readonly');
    final done = Completer<Uint8List>();
    final request = txn.objectStore('images').get(path.substring(12).toJS);
    request.onsuccess = ((web.Event _) {
      final value = request.result;
      if (value == null || value.isUndefinedOrNull) {
        done.completeError(StateError('找不到图片'));
      } else {
        done.complete((value as JSUint8Array).toDart);
      }
    }).toJS;
    request.onerror = ((web.Event _) => done.completeError(
      StateError('读取图片失败'),
    )).toJS;
    return done.future;
  }

  Future<Uint8List?> readCached(String reference) async {
    try {
      return await readBytes('local-image:cache:$reference');
    } catch (_) {
      return null;
    }
  }

  Future<void> cache(String reference, Uint8List bytes) async {
    final txn = (await _db).transaction('images'.toJS, 'readwrite');
    final done = _complete(txn);
    txn.objectStore('images').put(bytes.toJS, 'cache:$reference'.toJS);
    await done;
  }

  Future<void> delete(String path) async {
    if (!path.startsWith('local-image:')) return;
    final txn = (await _db).transaction('images'.toJS, 'readwrite');
    final done = _complete(txn);
    txn.objectStore('images').delete(path.substring(12).toJS);
    await done;
  }
}
