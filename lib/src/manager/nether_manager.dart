import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../types.dart';

class NetherManager {
  final String rootPath;

  NetherManager(this.rootPath);

  late final String _root = p.normalize(p.absolute(rootPath));

  String get _stateDir => p.join(_root, '.nether');

  String get _metadataFile => p.join(_stateDir, 'metadata.json');

  String get _overviewFile => p.join(_stateDir, 'overview.json');

  Map<String, FileMetadata>? readMetadata() {
    final file = File(_metadataFile);
    if (!file.existsSync()) return null;
    return _parseMetadata(file.readAsStringSync());
  }

  void writeMetadata(Map<String, FileMetadata> metadata) {
    _writeJson(_metadataFile, {
      for (final entry in metadata.entries) entry.key: entry.value.toMap(),
    });
  }

  void writeOverview(Map<String, dynamic> overview) {
    _writeJson(_overviewFile, overview);
  }

  void _writeJson(String path, Object value) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(value));
  }

  static Map<String, FileMetadata> _parseMetadata(String text) {
    final raw = jsonDecode(text) as Map<String, dynamic>;

    return {
      for (final entry in raw.entries)
        entry.key: (
          extension: entry.value['extension'] as String,
          language: entry.value['language'] as String,
          size: entry.value['size'] as int,
          mtime: entry.value['mtime'] as int,
          loc: entry.value['loc'] as int,
          classification: entry.value['classification'] as String,
          directory: entry.value['directory'] as String,
          depth: entry.value['depth'] as int,
        ),
    };
  }
}
