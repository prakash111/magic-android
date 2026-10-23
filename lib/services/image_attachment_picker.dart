import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'extension_workflow_service.dart';
import 'mobile_api.dart';

class ImageAttachmentPicker {
  final ImagePicker picker;
  ImageAttachmentPicker({ImagePicker? picker})
    : picker = picker ?? ImagePicker();
  static const _pendingModule = 'pending_studio_image_module';
  static const _pendingField = 'pending_studio_image_field';
  static const _recoveredPath = 'recovered_studio_image_path';
  static const _recoveredName = 'recovered_studio_image_name';
  static Future<void>? _recovery;

  Future<WorkflowFile?> pick({
    required String moduleId,
    required String field,
    int maxBytes = 5 * 1024 * 1024,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingModule, moduleId);
    await prefs.setString(_pendingField, field);
    try {
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (file == null) {
        await _clear(prefs);
        return null;
      }
      final attachment = await cache(file, maxBytes: maxBytes);
      await _clear(prefs);
      return attachment;
    } on PlatformException catch (error) {
      await _clear(prefs);
      throw ApiFailure(
        error.code.contains('denied') || error.code.contains('restricted')
            ? 'Photo access was denied. Allow access in device Settings, then choose a photo again.'
            : 'The photo picker could not open this image. Try a JPEG, PNG or WebP photo.',
      );
    } catch (_) {
      await _clear(prefs);
      rethrow;
    }
  }

  static Future<WorkflowFile> cache(
    XFile file, {
    int maxBytes = 5 * 1024 * 1024,
  }) async {
    final length = await file.length();
    if (length == 0) {
      throw const ApiFailure(
        'The selected photo is empty. Choose another image.',
      );
    }
    if (length > maxBytes) {
      throw ApiFailure(
        'Choose a photo smaller than ${(maxBytes / 1024 / 1024).toStringAsFixed(0)} MB.',
      );
    }
    final bytes = await file.readAsBytes();
    final mime = imageMimeType(bytes);
    if (mime == null) {
      throw const ApiFailure('Choose a valid JPEG, PNG or WebP image.');
    }
    final extension = {
      'image/jpeg': 'jpg',
      'image/png': 'png',
      'image/webp': 'webp',
    }[mime]!;
    var name = file.name
        .split(RegExp(r'[/\\]'))
        .last
        .replaceAll(RegExp(r'[\r\n"\x00-\x1f]'), '_');
    if (name.isEmpty) name = 'photo.$extension';
    if (!RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false).hasMatch(name)) {
      name = '$name.$extension';
    }
    String? path;
    if (!kIsWeb) {
      final directory = await Directory.systemTemp.createTemp('magicai-image-');
      path = '${directory.path}/photo.$extension';
      await File(path).writeAsBytes(bytes, flush: true);
    }
    return WorkflowFile(name, bytes, mimeType: mime, path: path);
  }

  static String? imageMimeType(List<int> bytes) {
    if (bytes.length >= 8 &&
        listEquals(bytes.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10])) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255) {
      return 'image/jpeg';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') {
      return 'image/webp';
    }
    return null;
  }

  static Future<void> recoverLostSelection() => _recovery ??= _recover();
  static Future<void> _recover() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_pendingModule) == null) return;
      final response = await ImagePicker().retrieveLostData();
      final file = response.files?.firstOrNull;
      if (file != null) {
        final cached = await cache(file, maxBytes: 50 * 1024 * 1024);
        await prefs.setString(_recoveredPath, cached.path!);
        await prefs.setString(_recoveredName, cached.name);
      }
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    } on ApiFailure {
      return;
    } on FileSystemException {
      return;
    }
  }

  static Future<(String, WorkflowFile)?> takeRecovered(String moduleId) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_pendingModule) != moduleId) return null;
    await recoverLostSelection();
    final field = prefs.getString(_pendingField),
        path = prefs.getString(_recoveredPath);
    if (field == null || path == null || kIsWeb) return null;
    try {
      final bytes = await File(path).readAsBytes();
      final mime = imageMimeType(bytes);
      if (mime == null) return null;
      return (
        field,
        WorkflowFile(
          prefs.getString(_recoveredName) ?? 'photo.jpg',
          Uint8List.fromList(bytes),
          mimeType: mime,
          path: path,
        ),
      );
    } on FileSystemException {
      return null;
    } finally {
      await _clear(prefs);
    }
  }

  static Future<void> _clear(SharedPreferences prefs) async {
    for (final key in [
      _pendingModule,
      _pendingField,
      _recoveredPath,
      _recoveredName,
    ]) {
      await prefs.remove(key);
    }
  }
}
