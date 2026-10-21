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
