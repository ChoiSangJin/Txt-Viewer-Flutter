import 'package:flutter/services.dart';
import 'folder_models.dart';

/// Android SAF and app-private persistence. No network or broad storage access.
class ReaderPlatform {
  static const channel = MethodChannel('txt_viewer/storage');
  Future<Map<String, dynamic>?> pickBook() async {
    final result = await channel.invokeMapMethod<String, dynamic>('pickBook');
    return result;
  }

  Future<FavoriteFolder?> pickFolder() async {
    final result = await channel.invokeMapMethod<String, dynamic>('pickFolder');
    return result == null ? null : FavoriteFolder.fromJson(result);
  }

  Future<FolderListing> listFolder(
    String treeUri, {
    String? parentUri,
    String query = '',
  }) async {
    final result = await channel.invokeMapMethod<String, dynamic>(
      'listFolder',
      {'treeUri': treeUri, 'parentUri': parentUri, 'query': query},
    );
    return FolderListing.fromJson(result!);
  }

  Future<bool> authorizeFolder(String uri) async =>
      await channel.invokeMapMethod<String, dynamic>('authorizeFolder', uri) !=
      null;
  Future<void> deleteDocument(
    String treeUri,
    String documentUri,
    String expectedName,
  ) => channel.invokeMethod('deleteDocument', {
    'treeUri': treeUri,
    'documentUri': documentUri,
    'expectedName': expectedName,
  });

  Future<void> cancelFolderScan() => channel.invokeMethod('cancelFolderScan');
  Future<void> releaseFolder(String uri) =>
      channel.invokeMethod('releaseFolder', uri);
  Future<Map<String, dynamic>> importDocument(String uri) async =>
      (await channel.invokeMapMethod<String, dynamic>('importDocument', uri))!;

  Future<Map<String, dynamic>?> loadPageIndex(String bookId, String layout) =>
      channel.invokeMapMethod<String, dynamic>('loadPageIndex', {
        'bookId': bookId,
        'layout': layout,
      });
  Future<void> savePageIndex(
    String bookId,
    String layout,
    String token,
    List<int> ends,
  ) => channel.invokeMethod('savePageIndex', {
    'bookId': bookId,
    'layout': layout,
    'token': token,
    'ends': ends,
  });

  Future<String> readBook(String id) async =>
      (await channel.invokeMethod<String>('readBook', id))!;
  Future<String?> loadState() => channel.invokeMethod<String>('loadState');
  Future<void> saveState(String state) =>
      channel.invokeMethod('saveState', state);
  Future<void> setReading(bool enabled) =>
      channel.invokeMethod('setReading', enabled);
}
