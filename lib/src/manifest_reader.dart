import 'dart:io';

import 'package:path/path.dart' as p;

import 'manifest.dart';
import 'types.dart';

class ManifestReader {
  final String rootPath;

  ManifestReader(this.rootPath);

  late final String _root = p.normalize(p.absolute(rootPath));

  Future<Map<String, ManifestDetails>> read(Iterable<String> paths) async {
    final result = <String, ManifestDetails>{};

    for (final path in paths) {
      final file = File(p.joinAll([_root, ...path.split('/')]));
      try {
        if (!await file.exists()) continue;
        result[path] = parseManifest(path, await file.readAsString());
      } on FileSystemException {
        continue;
      } on FormatException {
        result[path] = ManifestDetails.empty;
      }
    }

    return result;
  }
}
