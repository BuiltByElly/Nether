import 'dart:convert';
import 'dart:io' as io;

import 'package:nether/src/types.dart';
import 'package:path/path.dart' as p;

import 'package:nether/src/repo_scanner.dart';

Map<String, FileMetadata> parseMetadataJSON(String text) {
  final raw = jsonDecode(text) as Map<String, dynamic>;

  return {
    for (final j in raw.entries)
      j.key: (
        extension: j.value['extension'] as String,
        language: j.value['language'] as String,
        size: j.value['size'] as int,
        mtime: j.value['mtime'] as int,
        loc: j.value['loc'] as int,
        classification: j.value['classification'] as String,
        directory: j.value['directory'] as String,
        depth: j.value['depth'] as int,
      ),
  };
}

Future<void> main(List<String> args) async {
  final root = args.isEmpty ? '.' : args[0];
  final cache = io.File(p.join(root, '.nether', 'metadata.json'));

  final previous = cache.existsSync()
      ? parseMetadataJSON(cache.readAsStringSync())
      : null;
  final rawResult = await RepoScanner(root).metadata(previous: previous);

  final result = rawResult.map((key, record) => MapEntry(key, record.toMap()));

  cache.parent.createSync(recursive: true);
  cache.writeAsStringSync(jsonEncode(result));
  print('${result.length} files');
}
