import 'package:path/path.dart' as p;

import 'manager/nether_manager.dart';
import './orient/manifest_reader.dart';
import './orient/overview.dart';
import './orient/metadata.dart';
import 'types.dart';

class Nether {
  final String rootPath;
  final Metadata _metadata;
  final ManifestReader _manifestReader;
  final NetherManager _manager;

  Nether(this.rootPath)
    : _metadata = Metadata(rootPath),
      _manifestReader = ManifestReader(rootPath),
      _manager = NetherManager(rootPath);

  ///Returns the metadata of the current project
  Future<Map<String, FileMetadata>> metadata() async {
    final previous = _manager.readMetadata();
    final metadata = await _metadata.metadata(previous: previous);
    _manager.writeMetadata(metadata);
    return metadata;
  }

  ///Returns the overview of the current project
  Future<Map<String, dynamic>> overview() async {
    final repoMetadata = await metadata();
    final manifests = await _manifestReader.read(
      repoMetadata.entries
          .where((entry) => entry.value.classification == 'manifest')
          .map((entry) => entry.key),
    );
    final rootName = p.basename(p.normalize(p.absolute(rootPath)));
    final result = buildOverview(
      repoMetadata,
      rootName: rootName,
      manifests: manifests,
    );
    _manager.writeOverview(result.toMap());
    return result.toMap();
  }
}
