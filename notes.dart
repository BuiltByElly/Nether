// import 'dart:convert';
// import 'dart:io';

// import 'package:crypto/crypto.dart';
// import 'package:path/path.dart' as p;

// /// Directories that are never descended into.
// const _ignoredDirs = {
//   '.git',
//   '.dart_tool',
//   '.idea',
//   '.vscode',
//   '.gradle',
//   'node_modules',
//   'build',
//   '__pycache__',
// };

// const _languages = {
//   '.dart': 'Dart',
//   '.py': 'Python',
//   '.ts': 'TypeScript',
//   '.tsx': 'TypeScript',
//   '.js': 'JavaScript',
//   '.jsx': 'JavaScript',
//   '.java': 'Java',
//   '.kt': 'Kotlin',
//   '.swift': 'Swift',
//   '.go': 'Go',
//   '.rs': 'Rust',
//   '.c': 'C',
//   '.h': 'C',
//   '.cpp': 'C++',
//   '.hpp': 'C++',
//   '.cs': 'C#',
//   '.rb': 'Ruby',
//   '.php': 'PHP',
//   '.sh': 'Shell',
//   '.sql': 'SQL',
//   '.html': 'HTML',
//   '.css': 'CSS',
//   '.scss': 'SCSS',
//   '.md': 'Markdown',
//   '.json': 'JSON',
//   '.yaml': 'YAML',
//   '.yml': 'YAML',
//   '.toml': 'TOML',
//   '.xml': 'XML',
// };

// const _binaryExts = {
//   '.png',
//   '.jpg',
//   '.jpeg',
//   '.gif',
//   '.webp',
//   '.ico',
//   '.pdf',
//   '.zip',
//   '.gz',
//   '.tar',
//   '.7z',
//   '.jar',
//   '.so',
//   '.dll',
//   '.exe',
//   '.dylib',
//   '.class',
//   '.ttf',
//   '.otf',
//   '.woff',
//   '.woff2',
//   '.mp3',
//   '.mp4',
//   '.mov',
//   '.wasm',
//   '.apk',
//   '.aab',
// };

// const _docExts = {'.md', '.markdown', '.rst', '.txt', '.adoc'};
// const _docNames = {
//   'readme',
//   'license',
//   'licence',
//   'changelog',
//   'contributing',
//   'authors',
//   'notice',
// };
// const _docDirs = {'docs', 'doc', 'documentation'};

// const _configExts = {
//   '.yaml',
//   '.yml',
//   '.json',
//   '.toml',
//   '.ini',
//   '.cfg',
//   '.conf',
//   '.env',
//   '.xml',
//   '.properties',
//   '.gradle',
// };
// const _configNames = {
//   'dockerfile',
//   'makefile',
//   'cmakelists.txt',
//   'gemfile',
//   'go.mod',
//   'requirements.txt',
//   '.gitignore',
//   '.gitattributes',
//   '.dockerignore',
//   '.editorconfig',
//   '.npmrc',
// };

// // Generated / lock / minified output across ecosystems.
// const _generatedSuffixes = [
//   '.g.dart',
//   '.freezed.dart',
//   '.pb.dart',
//   '.pb.go',
//   '.pb.cc',
//   '.pb.h',
//   '_pb2.py',
//   '_pb2_grpc.py',
//   '.generated.ts',
//   '.generated.cs',
//   '.designer.cs',
//   '.min.js',
//   '.min.css',
//   '.map',
//   '.lock',
// ];
// const _generatedNames = {'package-lock.json', 'pnpm-lock.yaml', 'go.sum'};
// const _generatedDirs = {'generated', '__generated__', 'gen', 'dist', 'build'};

// const _testDirs = {'test', 'tests', '__tests__', 'spec', 'specs'};
// final _testNameLower = RegExp(
//   r'(^test_.+|_test\.\w+$|\.test\.\w+$|\.spec\.\w+$|_spec\.\w+$)',
// );
// final _testNameCased = RegExp(r'Tests?\.(java|kt|cs|swift)$'); // FooTest.java

// /// Recursively walks [rootPath] and returns, per file (keyed by path relative
// /// to the root, using `/` separators):
// ///   extension, language, size (bytes), loc, hash (sha256),
// ///   classification, directory, depth
// Future<Map<String, Map<String, String>>> indexDirectory(
//   String rootPath, {
//   String? currentPath, // internal: used by the recursion
//   Map<String, Map<String, String>>? acc, // internal: shared result map
// }) async {
//   final root = p.normalize(p.absolute(rootPath));
//   final result = acc ?? <String, Map<String, String>>{};

//   await for (final entity in Directory(
//     currentPath ?? root,
//   ).list(followLinks: false)) {
//     if (entity is Directory) {
//       if (_ignoredDirs.contains(p.basename(entity.path))) continue;
//       await indexDirectory(root, currentPath: entity.path, acc: result);
//     } else if (entity is File) {
//       final rel = p.relative(entity.path, from: root).replaceAll(r'\', '/');
//       try {
//         result[rel] = await _describeFile(entity, rel);
//       } on FileSystemException {
//         // Unreadable file (permissions, broken handle): skip it.
//       }
//     }
//   }
//   return result;
// }

// Future<Map<String, String>> _describeFile(File file, String rel) async {
//   final name = p.basename(rel);
//   final ext = p.extension(name).toLowerCase();
//   final size = await file.length();
//   final binary = _binaryExts.contains(ext) || await _looksBinary(file);

//   final loc = binary ? 0 : await _countLoc(file);
//   final hash = (await sha256.bind(file.openRead()).first).toString();
//   final dir = p.posix.dirname(rel);

//   return {
//     'extension': ext,
//     'language': binary ? 'binary' : (_languages[ext] ?? 'unknown'),
//     'size': size.toString(),
//     'loc': loc.toString(),
//     'hash': hash,
//     'classification': _classify(rel, name, ext, binary),
//     'directory': dir,
//     'depth': (dir == '.' ? 0 : dir.split('/').length).toString(),
//   };
// }

// /// Heuristic: a NUL byte in the first 8 KB means binary.
// Future<bool> _looksBinary(File file) async {
//   final raf = await file.open();
//   try {
//     final head = await raf.read(8192);
//     return head.contains(0);
//   } finally {
//     await raf.close();
//   }
// }

// /// Non-blank lines, read as a stream so large files don't load into memory.
// Future<int> _countLoc(File file) async {
//   var count = 0;
//   final lines = file
//       .openRead()
//       .transform(const Utf8Decoder(allowMalformed: true))
//       .transform(const LineSplitter());
//   await for (final line in lines) {
//     if (line.trim().isNotEmpty) count++;
//   }
//   return count;
// }

// extension _DropLast<T> on List<T> {
//   List<T> dropLast() => isEmpty ? this : sublist(0, length - 1);
// }

// String _classify(String rel, String name, String ext, bool binary) {
//   if (binary) return 'binary';

//   final lowerName = name.toLowerCase();
//   // Parent folders only, so a file named "test" or "docs" isn't mistaken for a folder.
//   final dirs = p.posix
//       .split(rel)
//       .dropLast()
//       .map((s) => s.toLowerCase())
//       .toSet();

//   if (_generatedNames.contains(lowerName) ||
//       _generatedSuffixes.any(lowerName.endsWith) ||
//       dirs.any(_generatedDirs.contains)) {
//     return 'generated';
//   }
//   if (dirs.any(_testDirs.contains) ||
//       _testNameLower.hasMatch(lowerName) ||
//       _testNameCased.hasMatch(name)) {
//     return 'test';
//   }
//   if (_docExts.contains(ext) ||
//       _docNames.contains(p.basenameWithoutExtension(lowerName)) ||
//       dirs.any(_docDirs.contains)) {
//     return 'documentation';
//   }
//   if (_configNames.contains(lowerName) ||
//       _configExts.contains(ext) ||
//       lowerName.contains('.config.') || // vite.config.ts, jest.config.js...
//       (lowerName.startsWith('.') && lowerName.endsWith('rc'))) {
//     // .eslintrc, .babelrc
//     return 'configuration';
//   }
//   if (_languages.containsKey(ext)) return 'source';
//   return 'other';
// }

// Future<void> main(List<String> args) async {
//   final data = await indexDirectory(args.isEmpty ? '.' : args.first);
//   print(const JsonEncoder.withIndent('  ').convert(data));
// }

import 'dart:io';

import 'package:path/path.dart' as p;

class RepoScanner {
  final String rootPath;

  RepoScanner(this.rootPath);

  Future<Map<String, Map<String, String>>> metadata() async {
    String? currentPath;
    Map<String, Map<String, String>>? acc;
    List<String> ignoredDirs = [];

    final root = p.normalize(p.absolute(rootPath));
    final result = acc ?? <String, Map<String, String>>{};

    await for (final entity in Directory(
      currentPath ?? root,
    ).list(followLinks: false)) {
      print(entity);
      if (entity is Directory) {
        if (ignoredDirs.contains(p.basename(entity.path))) continue;
        await indexDirectory(root, currentPath: entity.path, acc: result);
      } else if (entity is File) {
        final rel = p.relative(entity.path, from: root).replaceAll(r'\', '/');
        try {
          result[rel] = await _describeFile(entity, rel);
        } on FileSystemException {
          // Unreadable file (permissions, broken handle): skip it.
        }
      }
    }
    return result;
  }
}

void main() {
  RepoScanner("./").metadata();
}
