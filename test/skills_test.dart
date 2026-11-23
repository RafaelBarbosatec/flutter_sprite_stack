import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:skills_lint/skills_lint.dart';

void main() {
  test('skills/ passes skills_lint', () async {
    final config = await ConfigParser.loadConfig(path: 'skills_lint.yaml');
    expect(
      config.parsingErrors,
      isEmpty,
      reason: config.parsingErrors.join('\n'),
    );

    final valid = await validateSkills(
      skillDirPaths: const ['skills'],
      config: config,
      quiet: true,
    );

    expect(
      valid,
      isTrue,
      reason: 'Run `dart run skills_lint` for the detailed report.',
    );
  });

  test('skill directories are prefixed with the package name', () {
    final skills = Directory('skills')
        .listSync()
        .whereType<Directory>()
        .map((dir) => dir.uri.pathSegments.lastWhere((s) => s.isNotEmpty))
        .toList()
      ..sort();

    expect(skills, isNotEmpty);
    for (final name in skills) {
      expect(
        name.startsWith('flutter-sprite-stack-'),
        isTrue,
        reason: '$name must start with "flutter-sprite-stack-" so two '
            'dependencies cannot install the same skill directory.',
      );
      expect(File('skills/$name/SKILL.md').existsSync(), isTrue);
    }
  });
}
