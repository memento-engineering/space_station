import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:space_station_assets/src/attach_support.dart';
import 'package:test/test.dart';

import 'station_fixtures.dart';

void main() {
  test(
    'resolveStateWorkspace accepts a relative grid home with a real state store',
    () async {
      final gridHome = await bdInitGridHome('space-attach-relative-home-');
      addTearDown(() async {
        await gridHome.delete(recursive: true);
      });

      final previousCurrent = Directory.current;
      late final StateWorkspaceResult result;
      try {
        Directory.current = gridHome.path;
        result = resolveStateWorkspace(verb: 'status', stateWorkspacePath: '.');
      } finally {
        Directory.current = previousCurrent.path;
      }

      switch (result) {
        case StateWorkspaceFound(:final home, :final workspace):
          expect(home, '.');
          expect(
            p.equals(
              p.canonicalize(workspace.root),
              p.canonicalize(p.join(gridHome.path, '.grid')),
            ),
            isTrue,
          );
        case StateWorkspaceRefusal(:final message, :final code):
          fail('expected StateWorkspaceFound, got refusal $code: $message');
      }
    },
  );

  test(
    'resolveStateWorkspace refuses to walk up to a dual-role home work store',
    () async {
      final gridHome = await bdInitWorkspace('space-attach-work-store-home-');
      addTearDown(() async {
        await gridHome.delete(recursive: true);
      });
      Directory(p.join(gridHome.path, '.grid')).createSync();

      final result = resolveStateWorkspace(
        verb: 'status',
        stateWorkspacePath: gridHome.path,
      );

      switch (result) {
        case StateWorkspaceFound():
          fail('expected StateWorkspaceRefusal for a work-store walk-up');
        case StateWorkspaceRefusal(:final message, :final code):
          expect(code, 1);
          expect(
            message,
            allOf(
              contains('space status: no grid state store'),
              contains('${p.join(gridHome.path, '.grid')}/.beads'),
            ),
          );
      }
    },
  );

  test(
    'resolveStateWorkspace still refuses a home without a nested state store',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'space-attach-missing-home-',
      );
      final gridHome = Directory(dir.resolveSymbolicLinksSync());
      addTearDown(() async {
        await gridHome.delete(recursive: true);
      });

      final result = resolveStateWorkspace(
        verb: 'status',
        stateWorkspacePath: gridHome.path,
      );

      switch (result) {
        case StateWorkspaceFound():
          fail('expected StateWorkspaceRefusal for a missing state store');
        case StateWorkspaceRefusal(:final message, :final code):
          expect(code, 1);
          expect(
            message,
            allOf(
              contains('space status: no grid state store'),
              contains('${p.join(gridHome.path, '.grid')}/.beads'),
            ),
          );
      }
    },
  );
}
