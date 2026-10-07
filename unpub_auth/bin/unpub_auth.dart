import 'dart:io';

import 'package:args/args.dart';
import 'package:console/console.dart';
import 'package:unpub_auth/unpub_auth.dart' as unpub_auth;
import 'package:unpub_auth/utils.dart';

void main(List<String> arguments) async {
  final parser = ArgParser();
  parser.addCommand('login');
  parser.addCommand('logout');
  parser.addCommand('migrate');
  parser.addCommand('get');
  parser.addFlag('help', abbr: 'h', negatable: false, help: 'Show this usage.');

  final ArgResults result;
  try {
    result = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    _printUsage();
    exit(64);
  }
  if (result['help'] == true) {
    _printUsage();
    exit(0);
  }

  unpub_auth.Flow flow = unpub_auth.Flow.getToken;

  Object? subArgs;

  switch (result.command?.name) {
    case 'login':
      flow = unpub_auth.Flow.login;
      break;
    case 'logout':
      flow = unpub_auth.Flow.logout;
      break;
    case 'migrate':
      flow = unpub_auth.Flow.migrate;
      if (result.command?.arguments.length != 1) {
        Utils.stdoutPrint("unpub_auth migrate need a path argument");
        exit(1);
      }
      subArgs = result.command?.arguments.first;
      break;
    case 'get':
      flow = unpub_auth.Flow.getToken;
      break;
    default:
      _printUsage();
      exit(0);
  }

  await unpub_auth.run(flow: flow, args: subArgs);
  exit(0);
}

void _printUsage() {
  stdout.write(
    format('''
An auth tool for unpub. unpub is using Google OAuth2 by default. There's two situations where the unpub_auth can be used.

{@yellow}1. Login locally, and publish pub packages locally.{@end}
  {@blue}step 1.{@end} Call `unpub_auth login` when you first use it, and it will save credentials locally.
  {@blue}step 2.{@end} Before calling `dart pub publish` or `flutter pub publish`, call `unpub_auth get | dart pub token add <self-hosted-pub-server>`
  
{@yellow}2. Login locally, and publish pub packages from CI/CD.{@end}
{@yellow}   On CI/CD host device, you may not have opportunity to call `unpub_auth login`, so you can use `unpub_auth migrate` to migrate the credentials file.{@end}
  {@blue}step 1.{@end} In local device, call `unpub_auth login` when you first use it, and it will save credentials locally.
  {@blue}step 2.{@end} Copy the credentials file which was generated in step 1 to CI/CD device.
  {@blue}step 3.{@end} In CI/CD device, call `unpub_auth migrate <credentials-file-path>`, so the CI/CD will have the same credentials file.
  {@blue}step 4.{@end} In CI/CD device, before calling `dart pub publish` or `flutter pub publish`, call `unpub_auth get | dart pub token add <self-hosted-pub-server>`

Usage: {@green}unpub_auth <command> [arguments]{@end}

Available commands:
  {@green}get{@end}             Refresh and get a new accessToken. Must login first.
  {@green}login{@end}           Login unpub_auth on Google APIs.
  {@green}logout{@end}          Delete local credentials file.
  {@green}migrate{@end} {@green}<path>{@end}  Migrate existed credentials file from path.
'''),
  );
}
