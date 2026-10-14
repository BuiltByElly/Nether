import 'dart:io' as io;

import 'package:nether/src/repo_discovery.dart';

void main(List<String> argument) async {
  var result = await indexDirectory(argument[0]);
  print(result);
}
