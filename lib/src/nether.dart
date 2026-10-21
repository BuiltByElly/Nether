import 'package:path/path.dart' as p;

import 'manager/nether_manager.dart';
import 'overview.dart';
import 'repo_scanner.dart';
import 'types.dart';

class Nether {
  final String rootPath;
  final RepoScanner _scanner;
  final NetherManager _manager;

  Nether(this.rootPath)
    : _scanner = RepoScanner(rootPath),
      _manager = NetherManager(rootPath);

  Future<Map<String, FileMetadata>> scan() async {
    final previous = _manager.readMetadata();
    final metadata = await _scanner.metadata(previous: previous);
    _manager.writeMetadata(metadata);
    return metadata;
  }

  Future<Map<String, dynamic>> overview() async {
    final metadata = await scan();
    final rootName = p.basename(p.normalize(p.absolute(rootPath)));
    final result = buildOverview(metadata, rootName: rootName);
    _manager.writeOverview(result);
    return result;
  }
}
