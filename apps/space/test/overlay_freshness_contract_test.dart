import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final testFileRoot = p.normalize(
    p.join(File.fromUri(Platform.script).parent.path, '..', '..', '..'),
  );
  final packageConfig = Platform.packageConfig;
  final repositoryRoot =
      File(p.join(testFileRoot, '.github', 'workflows', 'ci.yml')).existsSync()
      ? testFileRoot
      : p.normalize(File.fromUri(Uri.parse(packageConfig!)).parent.parent.path);

  test(
    'CI checks the installed overlay immediately after dependency resolution',
    () {
      final workflow = File(
        p.join(repositoryRoot, '.github', 'workflows', 'ci.yml'),
      ).readAsStringSync();
      const requiredBlock =
          '      - name: Resolve committed dependencies\n'
          '        run: dart pub get\n'
          '      - name: Check installed overlay freshness\n'
          '        run: dart run space:space assets install --check --no-diff';

      expect(workflow.contains(requiredBlock), isTrue);
    },
  );

  test('SessionStart uses space prime and rejects bare bd prime', () {
    final settings = File(
      p.join(repositoryRoot, '.claude', 'settings.json'),
    ).readAsStringSync();

    expect(
      settings.contains('"command": "dart run space:space prime --hook-json"'),
      isTrue,
    );
    expect(settings.contains('"command": "bd prime --hook-json"'), isFalse);
  });
}
