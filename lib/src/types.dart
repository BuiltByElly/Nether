typedef FileMetadata = ({
  String extension,
  String language,
  int size,
  int mtime,
  int loc,
  String classification,
  String directory,
  int depth,
});

extension FileMetadataToMap on FileMetadata {
  ///converts the FileMetadata record to a map
  Map<String, dynamic> toMap() {
    return {
      'extension': extension,
      'language': language,
      'size': size,
      'mtime': mtime,
      'loc': loc,
      'classification': classification,
      'directory': directory,
      'depth': depth,
    };
  }
}

typedef _ClassStats = ({int files, int loc});
typedef _Stats = ({int files, int loc, Map<String, _ClassStats> byClass});
typedef _Language = ({String name, int files, int loc, double share});
typedef _Project = ({
  String path,
  String ecosystem,
  String? name,
  String? description,
  Map<String, String>? scripts,
  List<String>? entryPoints,
});
typedef _Directory = ({String path, int files, int loc, String role});
typedef _Tests = ({List<String> dirs, int files});
typedef _Docs = ({String? readme, List<String> files});

typedef RepoOverview = ({
  String generatedAt,
  String root,
  _Stats stats,
  List<_Language> languages,
  List<_Project> projects,
  List<_Directory> directories,
  _Tests tests,
  _Docs docs,
});

extension RepoOverviewToMap on RepoOverview {
  Map<String, dynamic> toMap() {
    final o = this;
    return {
      'generatedAt': o.generatedAt,
      'root': o.root,
      'stats': {
        'files': o.stats.files,
        'loc': o.stats.loc,
        'byClass': {
          for (final e in o.stats.byClass.entries)
            e.key: {'files': e.value.files, 'loc': e.value.loc},
        },
      },
      'languages': [
        for (final l in o.languages)
          {'name': l.name, 'files': l.files, 'loc': l.loc, 'share': l.share},
      ],
      'projects': [
        for (final p in o.projects)
          {
            'path': p.path,
            'ecosystem': p.ecosystem,
            if (p.name != null) 'name': p.name,
            if (p.description != null) 'description': p.description,
            if (p.scripts != null) 'scripts': p.scripts,
            if (p.entryPoints != null) 'entryPoints': p.entryPoints,
          },
      ],
      'directories': [
        for (final d in o.directories)
          {'path': d.path, 'files': d.files, 'loc': d.loc, 'role': d.role},
      ],
      'tests': {'dirs': o.tests.dirs, 'files': o.tests.files},
      'docs': {'readme': o.docs.readme, 'files': o.docs.files},
    };
  }
}

class ManifestDetails {
  final String? name;
  final String? description;
  final Map<String, String> scripts;
  final List<String> entryPoints;

  const ManifestDetails({
    this.name,
    this.description,
    this.scripts = const {},
    this.entryPoints = const [],
  });

  static const empty = ManifestDetails();
}
