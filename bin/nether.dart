import 'package:nether/nether.dart';

Future<void> main(List<String> arguments) async {
  final root = arguments.isEmpty ? '.' : arguments[0];
  final nether = Nether(root);
  final overview = await nether.overview();
  final stats = overview['stats'] as Map<String, dynamic>;
  print('${stats['files']} files');
}
