import 'dart:convert';
import 'package:flutter/material.dart';
import 'platform.dart';

enum ReaderTheme { system, light, dark, black }

class ReadingSettings {
  String font = 'RIDIBatang';
  double fontSize = 20, lineHeight = 1.7, paragraphSpace = 12;
  ReaderTheme theme = ReaderTheme.system;
  Map<String, dynamic> toJson() => {'font': font, 'size': fontSize,
    'height': lineHeight, 'paragraph': paragraphSpace, 'theme': theme.name};
  ReadingSettings();
  ReadingSettings.fromJson(Map<String, dynamic> json) {
    if (['RIDIBatang', 'KoPubBatang', 'Pretendard'].contains(json['font'])) {
      font = json['font'] as String;
    }
    fontSize = ((json['size'] as num?)?.toDouble() ?? 20).clamp(14, 36).toDouble();
    lineHeight = ((json['height'] as num?)?.toDouble() ?? 1.7).clamp(1.2, 2.4).toDouble();
    paragraphSpace = ((json['paragraph'] as num?)?.toDouble() ?? 12).clamp(0, 32).toDouble();
    theme = ReaderTheme.values.firstWhere((v) => v.name == json['theme'],
        orElse: () => ReaderTheme.system);
  }
  TextStyle get style => TextStyle(fontFamily: font, fontSize: fontSize,
      height: lineHeight, letterSpacing: 0.2);
}

class Book {
  final String id, name;
  int offset;
  Book(this.id, this.name, {this.offset = 0});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'offset': offset};
  Book.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String, name = json['name'] as String,
        offset = (json['offset'] as int? ?? 0).clamp(0, 1 << 31);
}

class LibraryModel extends ChangeNotifier {
  final ReaderPlatform platform;
  ReadingSettings settings = ReadingSettings();
  final List<Book> books = [];
  Future<void> _writes = Future.value();
  String? persistenceError;
  LibraryModel(this.platform);
  Future<void> load() async {
    final raw = await platform.loadState();
    if (raw == null) return;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    settings = ReadingSettings.fromJson(json['settings'] as Map<String, dynamic>);
    books.addAll((json['books'] as List).map((v) => Book.fromJson(v as Map<String, dynamic>)));
  }
  Future<void> save() {
    final raw = jsonEncode({'settings': settings.toJson(),
      'books': books.map((b) => b.toJson()).toList()});
    _writes = _writes.then((_) => platform.saveState(raw)).catchError((Object error) {
      persistenceError = '읽기 기록을 저장하지 못했습니다: $error';
      notifyListeners();
    });
    return _writes;
  }
  void changed() { notifyListeners(); save(); }
}
