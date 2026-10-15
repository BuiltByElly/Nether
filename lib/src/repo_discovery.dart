import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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

// ---------------------------------------------------------------------------
// The tables below were referenced by the classifier but were not in the
// excerpt I received, so these are my defaults. Replace them with yours.
// All names are lowercase because they are compared against lowercased names.
// ---------------------------------------------------------------------------

/// Exact file names that are always machine-written.
const _generatedNames = {
  'package-lock.json',
  'yarn.lock',
  'pnpm-lock.yaml',
  'pubspec.lock',
  'poetry.lock',
  'cargo.lock',
  'composer.lock',
  'gemfile.lock',
  'go.sum',
};

/// Name endings that mark generated code (committed build_runner output, etc.).
const _generatedSuffixes = {
  '.g.dart',
  '.freezed.dart',
  '.gr.dart',
  '.mocks.dart',
  '.pb.dart',
  '.pbenum.dart',
  '.pbjson.dart',
  '.pbgrpc.dart',
  '.pb.go',
  '_pb2.py',
  '_pb2_grpc.py',
  '.min.js',
  '.min.css',
  '.map',
};

/// Directories whose contents are generated. Usually already gitignored, but
/// this still catches them in repos that have no .gitignore.
const _generatedDirs = {
  'generated',
  '__generated__',
  '.dart_tool',
  'build',
  'dist',
  'node_modules',
  '__pycache__',
  'coverage',
};

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

/// Never walked, never reported, whatever the .gitignore says. Git itself
/// never lists `.git`, so no .gitignore will ever mention it.
const _alwaysSkipped = {'.git', '.nether'};

/// How much of a file is checked for NUL bytes when guessing "binary".
const _sniffBytes = 8192;

/// Walks a repository and describes every file that .gitignore lets through.
///
/// [metadata] returns one entry per file, keyed by its path relative to the
/// root (always `/`-separated). Each entry holds:
///   extension, language, size (bytes), mtime (ms since epoch), loc
///   (non-blank lines), hash (sha256 hex), classification, directory, depth
///
/// Every .gitignore is read when the walk reaches its directory and applies to
/// that subtree. An ignored directory is never entered, so a .gitignore inside
/// it is never read (same as git).
class RepoScanner {
  final String rootPath;

  RepoScanner(this.rootPath);

  late final String _root = p.normalize(p.absolute(rootPath));

  /// Pass the result of an earlier run as [previous] to skip unchanged files:
  /// a file whose size and mtime both match its old entry is not read again.
  Future<Map<String, Map<String, String>>> metadata({
    Map<String, Map<String, String>>? previous,
  }) async {
    if (!await Directory(_root).exists()) {
      throw ArgumentError.value(rootPath, 'rootPath', 'Not a directory');
    }
    final result = <String, Map<String, String>>{};
    await _walk(
      Directory(_root),
      IgnoreMatcher.empty,
      previous ?? const <String, Map<String, String>>{},
      result,
    );
    return result;
  }

  Future<void> _walk(
    Directory dir,
    IgnoreMatcher inherited,
    Map<String, Map<String, String>> previous,
    Map<String, Map<String, String>> result,
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

Future<Map<String, String>> _describeFile(
  File file,
  String rel,
  Map<String, String>? previous,
) async {
  // Stat before reading: if the file changes mid-read, the stored mtime is the
  // older one, so the next run notices and re-reads it.
  final stat = await file.stat();
  final size = stat.size.toString();
  final mtime = stat.modified.millisecondsSinceEpoch.toString();

  if (previous != null &&
      previous['size'] == size &&
      previous['mtime'] == mtime) {
    return Map.of(previous);
  }

  final name = p.basename(rel);
  final ext = _extensionOf(name);
  final content = await _scanContent(
    file,
    knownBinary: _binaryExts.contains(ext),
  );
  final dir = p.posix.dirname(rel);

  return {
    'extension': ext,
    'language': content.binary ? 'binary' : (_languages[ext] ?? 'unknown'),
    'size': size,
    'mtime': mtime,
    'loc': content.loc.toString(),
    'hash': content.hash,
    'classification': _classify(rel, name, ext, content.binary),
    'directory': dir,
    'depth': (dir == '.' ? 0 : dir.split('/').length).toString(),
  };
}

/// Lowercased extension. Dotfiles such as `.gitignore` or `.editorconfig` use
/// their whole name, so they can match the extension tables.
String _extensionOf(String name) {
  final ext = p.extension(name).toLowerCase();
  if (ext.isNotEmpty) return ext;
  return name.startsWith('.') && name.length > 1 ? name.toLowerCase() : '';
}

/// One streaming pass over the file that produces everything content-based:
///   * sha256 of the bytes,
///   * a NUL byte in the first 8 KB means binary,
///   * loc = number of lines with at least one non-whitespace byte (a line
///     ends at `\n` or `\r`, so `\r\n` files count correctly).
/// Known-binary extensions skip the line counting but are still hashed.
Future<({bool binary, int loc, String hash})> _scanContent(
  File file, {
  required bool knownBinary,
}) async {
  final digest = _DigestSink();
  final hasher = sha256.startChunkedConversion(digest);
  var binary = knownBinary;
  var loc = 0;
  var lineHasContent = false;
  var offset = 0;

  await for (final chunk in file.openRead()) {
    hasher.add(chunk);
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
  hasher.close();

  if (!binary && lineHasContent) loc++;
  return (binary: binary, loc: binary ? 0 : loc, hash: digest.value.toString());
}

/// Collects the single digest produced by a chunked hash conversion.
class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
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

  if (_generatedNames.contains(lowerName) ||
      _generatedSuffixes.any(lowerName.endsWith) ||
      dirs.any(_generatedDirs.contains)) {
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
