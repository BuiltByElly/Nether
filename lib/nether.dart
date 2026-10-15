import 'dart:convert';
import 'dart:io' as io;

import 'package:nether/src/repo_discovery.dart';

void main(List<String> argument) async {
  var result = await RepoScanner(argument[0]).metadata();
  print(jsonEncode(result));
}
