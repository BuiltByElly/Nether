import 'dart:convert';
import 'dart:io';

import 'package:nether/src/types.dart';
import 'package:path/path.dart' as p;

import 'gitignore.dart';

const _languages = {
  '.dart': 'Dart',
  '.py': 'Python',
  '.ts': 'TypeScript',
  '.tsx': 'TypeScript',
  '.js': 'JavaScript',
  '.jsx': 'JavaScript',
  '.java': 'Java',
  '.kt': 'Kotlin',
  '.swift': 'Swift',
  '.go': 'Go',
  '.rs': 'Rust',
  '.c': 'C',
  '.h': 'C',
  '.cpp': 'C++',
  '.hpp': 'C++',
  '.cs': 'C#',
  '.rb': 'Ruby',
  '.php': 'PHP',
  '.sh': 'Shell',
  '.sql': 'SQL',
  '.html': 'HTML',
  '.css': 'CSS',
  '.scss': 'SCSS',
  '.md': 'Markdown',
  '.json': 'JSON',
  '.yaml': 'YAML',
  '.yml': 'YAML',
  '.toml': 'TOML',
  '.xml': 'XML',
};

const _binaryExts = {
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.ico',
  '.pdf',
  '.zip',
  '.gz',
  '.tar',
  '.7z',
  '.jar',
  '.so',
  '.dll',
  '.exe',
  '.dylib',
  '.class',
  '.ttf',
  '.otf',
  '.woff',
  '.woff2',
  '.mp3',
  '.mp4',
  '.mov',
  '.wasm',
  '.apk',
  '.aab',
};

const _docExts = {'.md', '.markdown', '.rst', '.txt', '.adoc'};

const _docDirs = {'docs', 'doc', 'documentation'};

const _configExts = {
  '.yaml',
  '.yml',
  '.json',
  '.toml',
  '.ini',
  '.cfg',
  '.conf',
  '.xml',
  '.properties',
  '.gradle',
  '.gitignore',
  '.mod',
  '.npmrc',
  '.editorconfig',
  '.gitattributes',
};

const _testDirs = {'test', 'tests', '__tests__', 'spec', 'specs'};
final _testNameLower = RegExp(
  r'(^test_.+|_test\.\w+$|\.test\.\w+$|\.spec\.\w+$|_spec\.\w+$)',
);
final _testNameCased = RegExp(r'Tests?\.(java|kt|cs|swift)$'); // FooTest.java

final _generatedName = RegExp(
  r'\.(g|gen|generated|freezed|gr|mocks|pb\w*|min|designer)\.[^.]+$'
  r'|_pb2(_grpc)?\.py$'
  r'|\.lockb?$|\.lock\.json$|-lock\.(json|ya?ml)$|^go\.sum$'
  r'|\.(js|css)\.map$',
);

/// Committed folders that are always generated. Build output, node_modules
/// and the like are left to .gitignore.
const _generatedDirs = {'generated', '__generated__'};

/// File stems (name without extension) that are documentation.
const _docNames = {
  'readme',
  'license',
  'licence',
  'changelog',
  'contributing',
  'authors',
  'notice',
  'code_of_conduct',
  'security',
  'history',
};

/// Exact file names that are configuration or build manifests.
const _configNames = {
  'pubspec.yaml',
  'analysis_options.yaml',
  'package.json',
  'tsconfig.json',
  'pyproject.toml',
  'setup.cfg',
  'requirements.txt',
  'pom.xml',
  'build.gradle',
  'settings.gradle',
  'go.mod',
  'cargo.toml',
  'composer.json',
  'gemfile',
  'dockerfile',
  'docker-compose.yml',
  'makefile',
  'cmakelists.txt',
};

const _alwaysSkipped = {'.git', '.nether', 'node_modules'};

const _sniffBytes = 8192;

class RepoScanner {
  final String rootPath;

  RepoScanner(this.rootPath);

  late final String _root = p.normalize(p.absolute(rootPath));

  /// Pass the result of an earlier run as [previous] to skip unchanged files:
  /// a file whose size and mtime both match its old entry is not read again.
  Future<Map<String, FileMetadata>> metadata({
    Map<String, FileMetadata>? previous,
  }) async {
    if (!await Directory(_root).exists()) {
      throw ArgumentError.value(rootPath, 'rootPath', 'Not a directory');
    }
    if (!Directory(p.join(Directory(_root).path, '.git')).existsSync()) {
      throw ArgumentError("Initialize this project into a git repository.");
    }
    final result = <String, FileMetadata>{};
    await _walk(
      Directory(_root),
      IgnoreMatcher.empty,
      previous ?? const <String, FileMetadata>{},
      result,
    );
    return result;
  }

  Future<void> _walk(
    Directory dir,
    IgnoreMatcher inherited,
    Map<String, FileMetadata> previous,
    Map<String, FileMetadata> result,
  ) async {
    final matcher = await _withLocalRules(dir, inherited);

    final List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } on FileSystemException {
      return; // Unreadable directory: skip it.
    }
    entries.sort((a, b) => a.path.compareTo(b.path));

    for (final entity in entries) {
      if (_alwaysSkipped.contains(p.basename(entity.path))) continue;
      final rel = _relative(entity.path);

      // Symlinks come back as Link (not File or Directory) and are skipped.
      if (entity is Directory) {
        if (matcher.isIgnored(rel, isDirectory: true)) continue;
        await _walk(entity, matcher, previous, result);
      } else if (entity is File) {
        if (matcher.isIgnored(rel, isDirectory: false)) continue;
        try {
          result[rel] = await _describeFile(entity, rel, previous[rel]);
        } on FileSystemException {
          // Unreadable file (permissions, deleted mid-scan): skip it.
        }
      }
    }
  }

  /// [inherited] plus this directory's own .gitignore, if it has one.
  Future<IgnoreMatcher> _withLocalRules(
    Directory dir,
    IgnoreMatcher inherited,
  ) async {
    final file = File(p.join(dir.path, '.gitignore'));
    try {
      if (!await file.exists()) return inherited;
      final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      final base = dir.path == _root ? '' : _relative(dir.path);
      final rules = IgnoreRuleSet.parse(text, baseDir: base);
      return rules.isEmpty ? inherited : inherited.add(rules);
    } on FileSystemException {
      return inherited;
    }
  }

  String _relative(String path) =>
      p.split(p.relative(path, from: _root)).join('/');
}

Future<FileMetadata> _describeFile(
  File file,
  String rel,
  FileMetadata? previous,
) async {
  final stat = await file.stat();

  if (previous != null &&
      previous.size == stat.size &&
      previous.mtime == stat.modified.millisecondsSinceEpoch) {
    return (
      extension: previous.extension,
      language: previous.language,
      size: stat.size,
      mtime: stat.modified.millisecondsSinceEpoch,
      loc: previous.loc,
      classification: previous.classification,
      directory: previous.directory,
      depth: previous.depth,
    );
  }

  final name = p.basename(rel);
  final ext = _extensionOf(name);
  final content = await _scanContent(
    file,
    knownBinary: _binaryExts.contains(ext),
  );
  final dir = p.posix.dirname(rel);

  return (
    extension: ext,
    language: content.binary ? 'binary' : (_languages[ext] ?? 'unknown'),
    size: stat.size,
    mtime: stat.modified.millisecondsSinceEpoch,
    loc: content.loc,
    classification: _classify(rel, name, ext, content.binary),
    directory: dir,
    depth: dir == '.' ? 0 : dir.split('/').length,
  );
}

/// Lowercased extension. Dotfiles such as `.gitignore` or `.editorconfig` use
/// their whole name, so they can match the extension tables.
String _extensionOf(String name) {
  final ext = p.extension(name).toLowerCase();
  if (ext.isNotEmpty) return ext;
  return name.startsWith('.') && name.length > 1 ? name.toLowerCase() : '';
}

/// One streaming pass over the file that produces everything content-based:
///   * a NUL byte in the first 8 KB means binary,
///   * loc = number of lines with at least one non-whitespace byte (a line
///     ends at `\n` or `\r`, so `\r\n` files count correctly).
/// Known-binary extensions skip the line counting but are still hashed.
Future<({bool binary, int loc})> _scanContent(
  File file, {
  required bool knownBinary,
}) async {
  var binary = knownBinary;
  var loc = 0;
  var lineHasContent = false;
  var offset = 0;

  await for (final chunk in file.openRead()) {
    if (!binary) {
      for (var i = 0; i < chunk.length; i++) {
        final b = chunk[i];
        if (b == 0 && offset + i < _sniffBytes) {
          binary = true;
          break;
        }
        if (b == 0x0A || b == 0x0D) {
          if (lineHasContent) {
            loc++;
            lineHasContent = false;
          }
        } else if (b != 0x20 && b != 0x09 && b != 0x0B && b != 0x0C) {
          lineHasContent = true;
        }
      }
    }
    offset += chunk.length;
  }

  if (!binary && lineHasContent) loc++;
  return (binary: binary, loc: binary ? 0 : loc);
}

extension _DropLast<T> on List<T> {
  List<T> dropLast() => isEmpty ? this : sublist(0, length - 1);
}

String _classify(String rel, String name, String ext, bool binary) {
  if (binary) return 'binary';

  final lowerName = name.toLowerCase();
  // Parent folders only, so a file named "test" or "docs" isn't mistaken for a folder.
  final dirs = p.posix
      .split(rel)
      .dropLast()
      .map((s) => s.toLowerCase())
      .toSet();

  if (_generatedName.hasMatch(lowerName) || dirs.any(_generatedDirs.contains)) {
    return 'generated';
  }
  if (dirs.any(_testDirs.contains) ||
      _testNameLower.hasMatch(lowerName) ||
      _testNameCased.hasMatch(name)) {
    return 'test';
  }
  // Exact config names win over the doc rules, so requirements.txt and
  // CMakeLists.txt are configuration even though they end in .txt.
  if (!_configNames.contains(lowerName) &&
      (_docExts.contains(ext) ||
          _docNames.contains(p.basenameWithoutExtension(lowerName)) ||
          dirs.any(_docDirs.contains))) {
    return 'documentation';
  }
  if (_configNames.contains(lowerName) ||
      _configExts.contains(ext) ||
      lowerName.contains('.config.') || // vite.config.ts, jest.config.js...
      (lowerName.startsWith('.') && lowerName.endsWith('rc'))) {
    // .eslintrc, .babelrc
    return 'configuration';
  }
  if (_languages.containsKey(ext)) return 'source';
  return 'other';
}
