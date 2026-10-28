import 'package:flutter/services.dart';

/// Android SAF and app-private persistence. No network or broad storage access.
class ReaderPlatform {
  static const channel = MethodChannel('txt_viewer/storage');
  Future<Map<String, dynamic>?> pickBook() async {
    final result = await channel.invokeMapMethod<String, dynamic>('pickBook');
    return result;
  }

  Future<String> readBook(String id) async =>
      (await channel.invokeMethod<String>('readBook', id))!;
  Future<String?> loadState() => channel.invokeMethod<String>('loadState');
  Future<void> saveState(String state) =>
      channel.invokeMethod('saveState', state);
  Future<void> setReading(bool enabled) =>
      channel.invokeMethod('setReading', enabled);
}
