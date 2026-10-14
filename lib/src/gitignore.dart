import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

class GitIgnoreParser {
  final List<Glob> _rules = [];

  GitIgnoreParser.parseString(String content) {
    for (var line in content.split('\n')) {
      line = line.trim();

      // Skip empty lines and comments
      if (line.isEmpty || line.startsWith('#')) continue;

      // Handle standard gitignore pattern conversions to standard glob
      // e.g., mapping folders to recursive globs if they end in '/'
      if (line.endsWith('/')) {
        line = '$line**';
      }
      if (!line.startsWith('/') && !line.startsWith('**')) {
        line = '**/$line';
      }

      _rules.add(Glob(line, context: p.Context(style: p.Style.posix)));
    }
  }

  /// Parses a .gitignore file directly from disk
  factory GitIgnoreParser.fromFile(File file) {
    return GitIgnoreParser.parseString(file.readAsStringSync());
  }

  /// Returns true if the file path matches any of the rules
  bool isIgnored(String filePath) {
    // Normalize path separators to POSIX (forward slashes) for standard glob matching
    final normalizedPath = p.posix.joinAll(p.split(filePath));
    return _rules.any((glob) => glob.matches(normalizedPath));
  }
}

//USAGE
// void main() {
//   const gitignoreContent = '''
//   # Ignore dependency directories
//   .dart_tool/
//   build/

//   # Ignore specific extensions
//   *.log
//   *.env
//   ''';

//   final parser = GitIgnoreParser.parseString(gitignoreContent);

//   print(parser.isIgnored('.dart_tool/package_config.json')); // true
//   print(parser.isIgnored('build/app.apk')); // true
//   print(parser.isIgnored('production.log')); // true
//   print(parser.isIgnored('lib/main.dart')); // false
// }
