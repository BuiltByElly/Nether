import 'package:nether/src/types.dart';

import 'manifest.dart';

Map<String, dynamic> buildOverview(
  Map<String, FileMetadata> metadata, {
  required String rootName,
  Map<String, ManifestDetails> manifests = const {},
}) {
  var totalLoc = 0;
  var testFiles = 0;
  String? readme;

  final classFiles = <String, int>{};
  final classLoc = <String, int>{};
  final langFiles = <String, int>{};
  final langLoc = <String, int>{};
  final dirFiles = <String, int>{};
  final dirLoc = <String, int>{};
  final dirClasses = <String, Map<String, int>>{};
  final testDirs = <String>{};
  final docFiles = <String>[];
  final projects = <Map<String, dynamic>>[];

  for (final entry in metadata.entries) {
    final path = entry.key;
    final m = entry.value;
    final cls = m.classification;

    // stats
    totalLoc += m.loc;
    classFiles[cls] = (classFiles[cls] ?? 0) + 1;
    classLoc[cls] = (classLoc[cls] ?? 0) + m.loc;

    // languages: only real code, so Markdown/JSON don't dominate the mix
    if (cls == 'source' || cls == 'test') {
      langFiles[m.language] = (langFiles[m.language] ?? 0) + 1;
      langLoc[m.language] = (langLoc[m.language] ?? 0) + m.loc;
    }

    // directories: group by the first path segment ('.' = files at the root)
    final slash = path.indexOf('/');
    final top = slash == -1 ? '.' : path.substring(0, slash);
    dirFiles[top] = (dirFiles[top] ?? 0) + 1;
    dirLoc[top] = (dirLoc[top] ?? 0) + m.loc;
    final counts = dirClasses.putIfAbsent(top, () => <String, int>{});
    counts[cls] = (counts[cls] ?? 0) + 1;

    // tests
    if (cls == 'test') {
      testFiles++;
      testDirs.add(m.directory);
    }

    // docs
    if (cls == 'documentation') {
      docFiles.add(path);
      if (readme == null &&
          m.depth == 0 &&
          path.toLowerCase().startsWith('readme')) {
        readme = path;
      }
    }

    // projects: one entry per manifest, enriched when the reader could
    // extract details for it.
    if (cls == 'manifest') {
      final details = manifests[path] ?? ManifestDetails.empty;
      projects.add({
        'path': path,
        'ecosystem': manifestEcosystem(path),
        if (details.name != null) 'name': details.name,
        if (details.description != null) 'description': details.description,
        if (details.scripts.isNotEmpty) 'scripts': details.scripts,
        if (details.entryPoints.isNotEmpty) 'entryPoints': details.entryPoints,
      });
    }
  }

  // languages list, biggest first
  final codeLoc = langLoc.values.fold<int>(0, (a, b) => a + b);
  final languages = langFiles.keys.map((lang) {
    final loc = langLoc[lang]!;
    final share = codeLoc == 0 ? 0.0 : loc / codeLoc;
    return <String, dynamic>{
      'name': lang,
      'files': langFiles[lang],
      'loc': loc,
      'share': double.parse(share.toStringAsFixed(3)),
    };
  }).toList()..sort((a, b) => (b['loc'] as int).compareTo(a['loc'] as int));

  // directories list; role = the class most files in that folder have
  String dominant(Map<String, int> counts) =>
      counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;

  final directories = (dirFiles.keys.toList()..sort())
      .map(
        (dir) => <String, dynamic>{
          'path': dir,
          'files': dirFiles[dir],
          'loc': dirLoc[dir],
          'role': dir == "." ? "root" : dominant(dirClasses[dir]!),
        },
      )
      .toList();

  projects.sort((a, b) => (a['path'] as String).compareTo(b['path'] as String));
  docFiles.sort();

  return {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'root': rootName,
    'stats': {
      'files': metadata.length,
      'loc': totalLoc,
      'byClass': {
        for (final c in classFiles.keys)
          c: {'files': classFiles[c], 'loc': classLoc[c]},
      },
    },
    'languages': languages,
    'projects': projects,
    'directories': directories,
    'tests': {'dirs': testDirs.toList()..sort(), 'files': testFiles},
    'docs': {'readme': readme, 'files': docFiles},
  };
}
