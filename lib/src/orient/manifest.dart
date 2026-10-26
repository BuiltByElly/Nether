import 'dart:convert';

import 'package:toml/toml.dart';
import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';

import 'package:nether/src/types.dart';

/// Exact filenames that mark a project manifest -> ecosystem.
const _manifestFiles = <String, String>{
  // Dart
  'pubspec.yaml': 'Dart',

  // JavaScript / TypeScript
  'package.json': 'Node/Bun',
  'deno.json': 'Deno',
  'deno.jsonc': 'Deno',

  // Python
  'pyproject.toml': 'Python',
  'requirements.txt': 'Python',
  'setup.py': 'Python',
  'setup.cfg': 'Python',
  'Pipfile': 'Python',

  // JVM
  'pom.xml': 'Java',
  'build.gradle': 'Java/Kotlin',
  'build.gradle.kts': 'Java/Kotlin',
  'settings.gradle': 'Java/Kotlin',
  'settings.gradle.kts': 'Java/Kotlin',
  'build.sbt': 'Scala',
  'project.clj': 'Clojure',

  // Apple
  'Package.swift': 'Swift',
  'Podfile': 'Swift',

  // Systems languages
  'go.mod': 'Go',
  'Cargo.toml': 'Rust',
  'CMakeLists.txt': 'C/C++',
  'meson.build': 'C/C++',

  // Scripting / web
  'Gemfile': 'Ruby',
  'composer.json': 'PHP',

  // Functional and others
  'mix.exs': 'Elixir',
  'gleam.toml': 'Gleam',
  'stack.yaml': 'Haskell',
  'cabal.project': 'Haskell',
  'Project.toml': 'Julia',
  'shard.yml': 'Crystal',
};

/// Manifests whose name changes per project (MyApp.csproj) but whose
/// extension is fixed -> ecosystem.
const _manifestExtensions = <String, String>{
  '.csproj': 'C#',
  '.fsproj': 'F#',
  '.vbproj': 'Visual Basic',
  '.sln': '.NET',
  '.slnx': '.NET',
  '.cabal': 'Haskell',
  '.gemspec': 'Ruby',
  '.podspec': 'Swift',
};

/// Returns the ecosystem if [path] is a project manifest, otherwise null.
String? manifestEcosystem(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;

  final exact = _manifestFiles[name];
  if (exact != null) return exact;

  final dot = name.lastIndexOf('.');
  if (dot <= 0) return null; // no extension, or a dotfile like .gitignore
  return _manifestExtensions[name.substring(dot).toLowerCase()];
}

/// Reads the parts of a manifest Nether cares about, regardless of format.
///
/// JSON, YAML, TOML and XML are parsed structurally. Everything else falls
/// back to a conservative key/value scan.
ManifestDetails parseManifest(String path, String content) {
  final data = _parseData(path, content);
  if (data == null) return _fromText(content);
  return _fromData(data);
}

enum _ManifestFormat { json, yaml, toml, xml, text }

_ManifestFormat _formatOf(String path) {
  final name = path.split(RegExp(r'[/\\]')).last.toLowerCase();
  if (name.endsWith('.json') || name.endsWith('.jsonc')) {
    return _ManifestFormat.json;
  }
  if (name.endsWith('.yaml') || name.endsWith('.yml')) {
    return _ManifestFormat.yaml;
  }
  if (name.endsWith('.toml')) return _ManifestFormat.toml;
  if (name.endsWith('.xml') ||
      name.endsWith('.csproj') ||
      name.endsWith('.fsproj') ||
      name.endsWith('.vbproj')) {
    return _ManifestFormat.xml;
  }
  return _ManifestFormat.text;
}

Object? _parseData(String path, String content) {
  try {
    switch (_formatOf(path)) {
      case _ManifestFormat.json:
        return jsonDecode(_stripJsonComments(content));
      case _ManifestFormat.yaml:
        return _normalizeYaml(loadYaml(content));
      case _ManifestFormat.toml:
        return TomlDocument.parse(content).toMap();
      case _ManifestFormat.xml:
        return _parseXml(content);
      case _ManifestFormat.text:
        return null;
    }
  } catch (_) {
    return null;
  }
}

String _stripJsonComments(String text) {
  final out = StringBuffer();
  var inString = false;
  var escaped = false;
  var i = 0;

  while (i < text.length) {
    final c = text[i];
    if (inString) {
      out.write(c);
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
      i++;
      continue;
    }
    if (c == '"') {
      inString = true;
      out.write(c);
      i++;
      continue;
    }
    if (c == '/' && i + 1 < text.length) {
      final next = text[i + 1];
      if (next == '/') {
        i += 2;
        while (i < text.length && text[i] != '\n' && text[i] != '\r') {
          i++;
        }
        continue;
      }
      if (next == '*') {
        i += 2;
        while (i + 1 < text.length && !(text[i] == '*' && text[i + 1] == '/')) {
          i++;
        }
        i = i + 2 <= text.length ? i + 2 : text.length;
        continue;
      }
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

Object? _normalizeYaml(Object? value) {
  if (value is YamlMap) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _normalizeYaml(entry.value),
    };
  }
  if (value is YamlList) {
    return <Object?>[for (final item in value) _normalizeYaml(item)];
  }
  return value;
}

Object? _parseXml(String content) {
  final document = XmlDocument.parse(content);
  final root = document.rootElement;
  return <String, dynamic>{root.localName: _xmlElementValue(root)};
}

Object? _xmlElementValue(XmlElement element) {
  final children = element.childElements.toList();
  if (children.isEmpty) {
    final text = element.innerText.trim();
    return text.isEmpty ? null : text;
  }

  final map = <String, dynamic>{};
  for (final child in children) {
    final value = _xmlElementValue(child);
    if (value == null) continue;
    final key = child.localName;
    final existing = map[key];
    if (existing == null) {
      map[key] = value;
    } else if (existing is List) {
      existing.add(value);
    } else {
      map[key] = [existing, value];
    }
  }
  return map.isEmpty ? null : map;
}

const _nameKeys = {
  'name',
  'projectname',
  'artifactid',
  'assemblyname',
  'rootnamespace',
  'app',
  'title',
};

const _descriptionKeys = {'description', 'summary', 'about'};

const _scriptKeys = {'scripts', 'tasks'};

const _entryPointKeys = [
  'main',
  'module',
  'entry',
  'entrypoint',
  'entrypoints',
  'exports',
  'bin',
  'mainclass',
  'startupobject',
];

const _containers = {
  'project',
  'package',
  'tool',
  'workspace',
  'module',
  'app',
  'application',
  'metadata',
  'info',
  'poetry',
};

const _skippedKeys = {
  'dependencies',
  'devdependencies',
  'peerdependencies',
  'optionaldependencies',
  'dependency',
  'dev-dependencies',
  'build-dependencies',
  'build_dependencies',
  'target',
  'targets',
  'profiles',
  'features',
  'plugins',
  'parent',
  'repositories',
  'resolutions',
  'overrides',
};

ManifestDetails _fromData(Object? data) {
  return ManifestDetails(
    name: _stringField(data, _nameKeys),
    description: _stringField(data, _descriptionKeys),
    scripts: _scriptsField(data),
    entryPoints: _entryPointFields(data),
  );
}

String? _stringField(Object? data, Set<String> keys) {
  final value = _lookup(data, keys);
  if (value is String) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
  if (value is num || value is bool) return value.toString();
  return null;
}

Map<String, String> _scriptsField(Object? data) {
  final value = _lookup(data, _scriptKeys);
  if (value is! Map) return const {};

  final scripts = <String, String>{};
  for (final entry in value.entries) {
    final command = _scalarText(entry.value);
    if (command != null) scripts[entry.key.toString()] = command;
  }
  return scripts;
}

String? _scalarText(Object? value) {
  if (value is String) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
  if (value is num || value is bool) return value.toString();
  if (value is List) {
    final parts = value.map(_scalarText).whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(' ');
  }
  return null;
}

List<String> _entryPointFields(Object? data) {
  final result = <String>[];

  void add(Object? value) {
    if (value is String) {
      final text = value.trim();
      if (text.isNotEmpty && !result.contains(text)) result.add(text);
    } else if (value is List) {
      for (final item in value) {
        add(item);
      }
    } else if (value is Map) {
      final path = _child(value, 'path');
      if (path is String) {
        add(path);
      } else {
        for (final item in value.values) {
          add(item);
        }
      }
    }
  }

  for (final key in _entryPointKeys) {
    add(_lookup(data, {key}));
  }
  return result;
}

Object? _lookup(Object? node, Set<String> keys, [int depth = 0]) {
  if (depth > 6) return null;

  if (node is Map) {
    for (final entry in node.entries) {
      if (keys.contains(entry.key.toString().toLowerCase())) {
        return entry.value;
      }
    }
    for (final container in _containers) {
      final child = _child(node, container);
      if (child == null) continue;
      final found = _lookup(child, keys, depth + 1);
      if (found != null) return found;
    }
    for (final entry in node.entries) {
      final key = entry.key.toString().toLowerCase();
      if (_skippedKeys.contains(key)) continue;
      final found = _lookup(entry.value, keys, depth + 1);
      if (found != null) return found;
    }
  } else if (node is List) {
    for (final value in node) {
      final found = _lookup(value, keys, depth + 1);
      if (found != null) return found;
    }
  }
  return null;
}

Object? _child(Map<dynamic, dynamic> map, String key) {
  for (final entry in map.entries) {
    if (entry.key.toString().toLowerCase() == key) return entry.value;
  }
  return null;
}

ManifestDetails _fromText(String content) {
  final name = _firstMatch(content, [
    RegExp(
      r'''^\s*(?:rootProject\.)?name\s*[:=]\s*["']?([^"'\r\n#]+)''',
      caseSensitive: false,
      multiLine: true,
    ),
    RegExp(
      r'''^\s*project\s*\(\s*["']?([^"'\s,)]+)''',
      caseSensitive: false,
      multiLine: true,
    ),
  ]);
  final description = _firstMatch(content, [
    RegExp(
      r'''^\s*(?:description|summary)\s*[:=]\s*["']?([^"'\r\n#]+)''',
      caseSensitive: false,
      multiLine: true,
    ),
  ]);
  final entryPoint = _firstMatch(content, [
    RegExp(
      r'''^\s*(?:mainClass|main|startupObject)\s*[:=]\s*["']?([^"'\r\n#]+)''',
      caseSensitive: false,
      multiLine: true,
    ),
  ]);

  return ManifestDetails(
    name: name,
    description: description,
    entryPoints: entryPoint == null ? const [] : [entryPoint],
  );
}

String? _firstMatch(String text, List<RegExp> patterns) {
  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    if (match == null) continue;
    final value = match.group(1)?.trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}
