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
        size: (j.value['size'] as num).toInt(),
        mtime: (j.value['mtime'] as num).toInt(),
        loc: (j.value['loc'] as num).toInt(),
        classification: j.value['classification'] as String,
        directory: j.value['directory'] as String,
        depth: (j.value['depth'] as num).toInt(),
      ),
  };
}

Future<void> main(List<String> args) async {
  final root = args.isEmpty ? '.' : args[0];
  final cache = io.File(p.join(root, '.nether', 'metadata.json'));

  final previous = cache.existsSync()
      ? parseMetadataJSON(cache.readAsStringSync())
      : null;
  final result = await RepoScanner(root).metadata(previous: previous);

  cache.parent.createSync(recursive: true);
  cache.writeAsStringSync(jsonEncode(result));
  print('${result.length} files');
}
