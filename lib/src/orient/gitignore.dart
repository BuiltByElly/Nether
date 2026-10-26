import 'dart:convert';

/// One compiled line of a .gitignore file.
class IgnoreRule {
  IgnoreRule._(
    this._regex, {
    required this.negated,
    required this.dirOnly,
    required this.anchored,
  });

  final RegExp _regex;

  /// The line started with `!`.
  final bool negated;

  /// The line ended with `/`, so it only matches directories.
  final bool dirOnly;

  /// The pattern has a `/` at the start or in the middle, so it is matched
  /// against the whole path below the .gitignore's directory. Otherwise it is
  /// matched against the entry's name at any depth.
  final bool anchored;

  /// Parses one line. Returns null for blank lines, comments and patterns
  /// git itself would reject.
  static IgnoreRule? parse(String rawLine) {
    var line = rawLine;

    // Trailing spaces are dropped unless escaped with a backslash.
    var end = line.length;
    while (end > 0 && line.codeUnitAt(end - 1) == 0x20) {
      var backslashes = 0;
      for (var k = end - 2; k >= 0 && line.codeUnitAt(k) == 0x5C; k--) {
        backslashes++;
      }
      if (backslashes.isOdd) break;
      end--;
    }
    line = line.substring(0, end);

    if (line.isEmpty || line.startsWith('#')) return null;

    var negated = false;
    if (line.startsWith('!')) {
      negated = true;
      line = line.substring(1);
    }

    var dirOnly = false;
    while (line.endsWith('/')) {
      dirOnly = true;
      line = line.substring(0, line.length - 1);
    }
    if (line.isEmpty) return null;

    final anchored = line.contains('/');
    if (line.startsWith('/')) line = line.substring(1);
    if (line.isEmpty) return null;

    final source = _globToRegex(line);
    if (source == null) return null;

    return IgnoreRule._(
      RegExp('^$source\$', dotAll: true),
      negated: negated,
      dirOnly: dirOnly,
      anchored: anchored,
    );
  }

  /// [path] is relative to the directory of the .gitignore this rule came
  /// from, uses `/` separators and has no leading slash.
  bool matches(String path, {required bool isDirectory}) {
    if (dirOnly && !isDirectory) return false;
    final target = anchored ? path : path.substring(path.lastIndexOf('/') + 1);
    return _regex.hasMatch(target);
  }

  static String? _globToRegex(String g) {
    final out = StringBuffer();
    var i = 0;
    while (i < g.length) {
      final c = g[i];
      if (c == r'\') {
        // A dangling backslash is invalid in git; drop the whole pattern.
        if (i + 1 >= g.length) return null;
        out.write(RegExp.escape(g[i + 1]));
        i += 2;
      } else if (c == '*') {
        var j = i;
        while (j < g.length && g[j] == '*') {
          j++;
        }
        final before = i == 0 || g[i - 1] == '/';
        final after = j == g.length || g[j] == '/';
        if (j - i >= 2 && before && after) {
          if (j == g.length) {
            // Whole pattern `**` matches everything; trailing `/**` matches
            // everything inside (but not the directory itself).
            out.write(i == 0 ? '.*' : '.+');
            i = j;
          } else {
            // `**/` matches zero or more directories.
            out.write('(?:.*/)?');
            i = j + 1;
          }
        } else {
          // A single `*` (or `**` glued to other characters) stays inside
          // one path segment.
          out.write('[^/]*');
          i = j;
        }
      } else if (c == '?') {
        out.write('[^/]');
        i++;
      } else if (c == '[') {
        final close = _classEnd(g, i);
        if (close == -1) {
          out.write(r'\[');
          i++;
        } else {
          var body = g.substring(i + 1, close);
          final negate = body.startsWith('!') || body.startsWith('^');
          if (negate) body = body.substring(1);
          body = body
              .replaceAll(r'\', r'\\')
              .replaceAll('[', r'\[')
              .replaceAll(']', r'\]');
          // Bracket expressions never match a slash.
          out.write(negate ? '[^$body/]' : '[$body]');
          i = close + 1;
        }
      } else {
        out.write(RegExp.escape(c));
        i++;
      }
    }
    return out.toString();
  }

  /// Index of the `]` closing the class opened at [open], or -1.
  static int _classEnd(String g, int open) {
    var k = open + 1;
    if (k < g.length && (g[k] == '!' || g[k] == '^')) k++;
    if (k < g.length && g[k] == ']') k++; // a leading `]` is a literal
    while (k < g.length) {
      if (g[k] == ']') return k;
      k++;
    }
    return -1;
  }
}

/// All rules from one .gitignore file, plus the directory it applies to.
class IgnoreRuleSet {
  final String baseDir;
  final List<IgnoreRule> rules;

  IgnoreRuleSet(this.baseDir, this.rules);

  /// Parses the text of a .gitignore. [baseDir] is the directory holding the
  /// file, relative to the repo root with `/` separators ('' for the root).
  factory IgnoreRuleSet.parse(String content, {String baseDir = ''}) {
    final text = content.startsWith('﻿') ? content.substring(1) : content;
    final rules = <IgnoreRule>[];
    for (final line in const LineSplitter().convert(text)) {
      final rule = IgnoreRule.parse(line);
      if (rule != null) rules.add(rule);
    }
    return IgnoreRuleSet(baseDir, rules);
  }

  bool get isEmpty => rules.isEmpty;

  /// `true` = ignored, `false` = re-included by a `!` rule, `null` = no rule
  /// in this file matches. [relPath] is relative to the repo root and must be
  /// inside [baseDir].
  bool? verdict(String relPath, {required bool isDirectory}) {
    final local = baseDir.isEmpty
        ? relPath
        : relPath.substring(baseDir.length + 1);
    for (var i = rules.length - 1; i >= 0; i--) {
      final rule = rules[i];
      if (rule.matches(local, isDirectory: isDirectory)) return !rule.negated;
    }
    return null;
  }
}

/// The rule sets in effect for one directory: its own .gitignore plus every
/// ancestor's, shallowest first. Immutable, so each directory can hold its own
/// matcher while the walk recurses.
class IgnoreMatcher {
  const IgnoreMatcher._(this._sets);

  static const empty = IgnoreMatcher._(<IgnoreRuleSet>[]);

  final List<IgnoreRuleSet> _sets;

  /// A matcher for a subdirectory that has its own .gitignore.
  IgnoreMatcher add(IgnoreRuleSet set) => IgnoreMatcher._([..._sets, set]);

  /// [relPath] is relative to the repo root, with `/` separators.
  bool isIgnored(String relPath, {required bool isDirectory}) {
    for (var i = _sets.length - 1; i >= 0; i--) {
      final verdict = _sets[i].verdict(relPath, isDirectory: isDirectory);
      if (verdict != null) return verdict;
    }
    return false;
  }
}
