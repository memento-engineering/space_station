import 'dart:io';
import 'dart:isolate';

import 'package:analyzer/dart/analysis/utilities.dart' show parseString;
import 'package:analyzer/dart/ast/ast.dart'
    show
        ClassDeclaration,
        CompilationUnit,
        ExportDirective,
        HideCombinator,
        PartDirective,
        ShowCombinator;
import 'package:args/command_runner.dart' show Command, CommandRunner;
import 'package:space_station_assets/space_station_assets.dart'
    show buildRunner;
import 'package:test/test.dart';

const _commandBarrels = <String, String>{
  'grid_assets': 'grid_assets.dart',
  'grid_cli': 'grid_cli.dart',
  'dart_grid_assets': 'dart_grid_assets.dart',
  'federated_grid_assets': 'federated_grid_assets.dart',
};

/// The explicit policy boundary for public dependency commands this baseline
/// runner intentionally does not compose. A key that disappears from the real
/// exported surface or a blank reason is a failing stale exception.
const _excludedCommands = <String, String>{
  'grid_assets:IndexCommand':
      '`index` requires an embedding provider and site binding that this '
      'baseline runner does not arm.',
  'grid_cli:UpCommand':
      '`up` is replaced by the station-context implementation in this package.',
  'grid_cli:DownCommand':
      '`down` is replaced by the station-context implementation in this '
      'package.',
  'grid_cli:StatusCommand':
      '`status` is replaced by the station-context implementation in this '
      'package.',
  'grid_cli:BeadCommand':
      '`bead` is an optional downstream resident UI not claimed by the '
      'baseline.',
  'grid_cli:BeadSetCommand':
      '`bead set` is an optional downstream resident UI not claimed by the '
      'baseline.',
  'grid_cli:BeadBoardCommand':
      '`bead board` is an optional downstream resident UI not claimed by the '
      'baseline.',
  'grid_cli:BeadRoundCommand':
      '`bead round` is an optional downstream resident UI not claimed by the '
      'baseline.',
  'grid_cli:SessionCommand':
      '`session` is standalone held-worktree maintenance outside this '
      'station baseline.',
  'grid_cli:SessionLsCommand':
      '`session ls` is standalone held-worktree maintenance outside this '
      'station baseline.',
  'grid_cli:SessionCollectCommand':
      '`session collect` is standalone held-worktree maintenance outside this '
      'station baseline.',
  'grid_cli:SubstationCommand':
      '`substation` mutates the live roster while this station authors its '
      'roster in SpaceDelegate.',
  'grid_cli:SubstationAttachCommand':
      '`substation attach` mutates the live roster while this station authors '
      'its roster in SpaceDelegate.',
  'grid_cli:SubstationDetachCommand':
      '`substation detach` mutates the live roster while this station authors '
      'its roster in SpaceDelegate.',
  'grid_cli:ReadCommand':
      '`read` is a standalone source-inspection utility, not a station '
      'operation.',
  'grid_cli:AssetCatalogCommand':
      '`asset-catalog` requires a station-specific catalog resolver that this '
      'runner does not compose.',
  'grid_cli:DemoCommand':
      '`demo` is the framework\'s throwaway reactivity demonstration.',
};

void main() {
  late Set<String> derived;
  late Set<String> observed;

  setUpAll(() {
    derived = _DependencyCommandScanner(_commandBarrels).discover();
    observed = _observedCommandTypeNames(buildRunner());
  });

  test(
    'every exported dependency Command is composed or explicitly excluded',
    () {
      expect(
        _unaccountedCommands(
          derived: derived,
          observedTypeNames: observed,
          exclusions: _excludedCommands,
        ),
        isEmpty,
      );
    },
  );

  test('every exclusion is current and carries an inline reason', () {
    final refusals = <String>[];
    for (final entry in _excludedCommands.entries) {
      if (!derived.contains(entry.key)) {
        refusals.add('stale exclusion ${entry.key} is not exported');
      }
      if (entry.value.trim().isEmpty) {
        refusals.add('exclusion ${entry.key} has a blank reason');
      }
    }
    expect(refusals..sort(), isEmpty);
  });

  test('guard refuses when ShowCommand is removed from the composed tree', () {
    final withoutShow = Set<String>.of(observed)..remove('ShowCommand');

    expect(
      _unaccountedCommands(
        derived: derived,
        observedTypeNames: withoutShow,
        exclusions: _excludedCommands,
      ),
      contains('uncomposed vended command grid_assets:ShowCommand'),
    );
  });
}

Set<String> _observedCommandTypeNames(CommandRunner<int> runner) {
  final observed = <String>{};

  void visit(Command<int> command) {
    observed.add(command.runtimeType.toString());
    for (final child in command.subcommands.values) {
      visit(child);
    }
  }

  for (final command in runner.commands.values) {
    visit(command);
  }
  return observed;
}

List<String> _unaccountedCommands({
  required Set<String> derived,
  required Set<String> observedTypeNames,
  required Map<String, String> exclusions,
}) {
  final refusals = <String>[
    for (final identity in derived)
      if (!observedTypeNames.contains(identity.split(':').last) &&
          !exclusions.containsKey(identity))
        'uncomposed vended command $identity',
  ]..sort();
  return refusals;
}

/// Discovers command classes from the source actually selected by pub. This is
/// intentionally a parser, not a handwritten command inventory: a producer
/// exporting a new concrete `Command<int>` changes the derived set immediately.
final class _DependencyCommandScanner {
  _DependencyCommandScanner(this.barrels);

  final Map<String, String> barrels;
  final Map<Uri, _SourceLibrary> _libraries = <Uri, _SourceLibrary>{};
  final Map<Uri, Map<String, _ClassShape>> _namespaces =
      <Uri, Map<String, _ClassShape>>{};
  final Map<Uri, Map<String, _ClassShape>> _classesByLibrary =
      <Uri, Map<String, _ClassShape>>{};
  final Map<String, List<_ClassShape>> _classesByName =
      <String, List<_ClassShape>>{};
  final Set<Uri> _resolving = <Uri>{};

  Set<String> discover() {
    final publicNamespaces = <String, Map<String, _ClassShape>>{};
    for (final entry in barrels.entries) {
      final uri = Isolate.resolvePackageUriSync(
        Uri.parse('package:${entry.key}/${entry.value}'),
      );
      if (uri == null) {
        throw StateError('cannot resolve package barrel for ${entry.key}');
      }
      publicNamespaces[entry.key] = _namespaceOf(_canonical(uri));
    }

    return <String>{
      for (final package in publicNamespaces.entries)
        for (final shape in package.value.values)
          if (shape.isConcrete && _isCommand(shape, <_ClassShape>{}))
            '${package.key}:${shape.name}',
    };
  }

  Map<String, _ClassShape> _namespaceOf(Uri uri) {
    final cached = _namespaces[uri];
    if (cached != null) return cached;
    // Export cycles contribute nothing on the recursive edge; the originating
    // library still contributes its own declarations and all non-cyclic arms.
    if (!_resolving.add(uri)) return const <String, _ClassShape>{};

    final library = _readLibrary(uri);
    final namespace = <String, _ClassShape>{
      for (final shape in library.classes)
        if (!shape.name.startsWith('_')) shape.name: shape,
    };
    for (final export in library.exports) {
      final target = _resolveExport(uri, export.uri);
      if (target == null) continue;
      final exported = Map<String, _ClassShape>.of(_namespaceOf(target));
      for (final combinator in export.combinators) {
        switch (combinator) {
          case _Show(:final names):
            exported.removeWhere((name, _) => !names.contains(name));
          case _Hide(:final names):
            exported.removeWhere((name, _) => names.contains(name));
        }
      }
      for (final entry in exported.entries) {
        namespace.putIfAbsent(entry.key, () => entry.value);
      }
    }

    _resolving.remove(uri);
    return _namespaces[uri] = Map<String, _ClassShape>.unmodifiable(namespace);
  }

  _SourceLibrary _readLibrary(Uri uri) {
    final cached = _libraries[uri];
    if (cached != null) return cached;

    final classes = <String, _ClassShape>{};
    final exports = <_ExportShape>[];
    final visitedUnits = <Uri>{};

    void readUnit(Uri unitUri, {required bool isEntry}) {
      final canonical = _canonical(unitUri);
      if (!visitedUnits.add(canonical)) return;
      final file = File.fromUri(canonical);
      if (!file.existsSync()) {
        throw StateError('exported Dart unit does not exist: ${file.path}');
      }
      final CompilationUnit unit = parseString(
        content: file.readAsStringSync(),
        path: file.path,
        // Keep every exported library strict. Generated parts can carry syntax
        // accepted under their package's language version that the standalone
        // latest-version parser diagnoses; its recovered AST still supplies
        // the declarations needed for the inheritance graph.
        throwIfDiagnostics: isEntry,
      ).unit;
      for (final declaration
          in unit.declarations.whereType<ClassDeclaration>()) {
        final superclass = declaration.extendsClause?.superclass;
        final superArguments = superclass?.typeArguments?.arguments;
        final shape = _ClassShape(
          library: uri,
          name: declaration.namePart.typeName.lexeme,
          superclass: superclass?.name.lexeme,
          directlyExtendsCommandInt:
              superclass?.name.lexeme == 'Command' &&
              superArguments?.length == 1 &&
              superArguments!.single.toSource() == 'int',
          isConcrete:
              declaration.abstractKeyword == null &&
              declaration.sealedKeyword == null,
        );
        classes[shape.name] = shape;
      }
      for (final directive in unit.directives.whereType<PartDirective>()) {
        final raw = directive.uri.stringValue;
        if (raw != null) readUnit(canonical.resolve(raw), isEntry: false);
      }
      if (!isEntry) return;
      for (final directive in unit.directives.whereType<ExportDirective>()) {
        final raw = directive.uri.stringValue;
        if (raw == null) continue;
        exports.add(
          _ExportShape(raw, <_ExportCombinator>[
            for (final combinator in directive.combinators)
              switch (combinator) {
                ShowCombinator() => _Show(
                  combinator.shownNames.map((name) => name.name).toSet(),
                ),
                HideCombinator() => _Hide(
                  combinator.hiddenNames.map((name) => name.name).toSet(),
                ),
              },
          ]),
        );
      }
    }

    readUnit(uri, isEntry: true);
    final library = _SourceLibrary(
      classes: List<_ClassShape>.unmodifiable(classes.values),
      exports: List<_ExportShape>.unmodifiable(exports),
    );
    _classesByLibrary[uri] = Map<String, _ClassShape>.unmodifiable(classes);
    for (final shape in classes.values) {
      _classesByName.putIfAbsent(shape.name, () => <_ClassShape>[]).add(shape);
    }
    return _libraries[uri] = library;
  }

  bool _isCommand(_ClassShape shape, Set<_ClassShape> visiting) {
    if (shape.directlyExtendsCommandInt) return true;
    final superclass = shape.superclass;
    if (superclass == null || !visiting.add(shape)) return false;
    final local = _classesByLibrary[shape.library]?[superclass];
    final candidates = local == null
        ? _classesByName[superclass] ?? const <_ClassShape>[]
        : <_ClassShape>[local];
    final result = candidates.any((parent) => _isCommand(parent, visiting));
    visiting.remove(shape);
    return result;
  }

  Uri? _resolveExport(Uri from, String raw) {
    final parsed = Uri.parse(raw);
    if (parsed.scheme == 'dart') return null;
    if (parsed.scheme == 'package') {
      final resolved = Isolate.resolvePackageUriSync(parsed);
      if (resolved == null) {
        throw StateError('cannot resolve exported package URI $raw from $from');
      }
      return _canonical(resolved);
    }
    return _canonical(from.resolveUri(parsed));
  }

  Uri _canonical(Uri uri) => File.fromUri(uri).absolute.uri;
}

final class _SourceLibrary {
  const _SourceLibrary({required this.classes, required this.exports});

  final List<_ClassShape> classes;
  final List<_ExportShape> exports;
}

final class _ClassShape {
  const _ClassShape({
    required this.library,
    required this.name,
    required this.superclass,
    required this.directlyExtendsCommandInt,
    required this.isConcrete,
  });

  final Uri library;
  final String name;
  final String? superclass;
  final bool directlyExtendsCommandInt;
  final bool isConcrete;
}

final class _ExportShape {
  const _ExportShape(this.uri, this.combinators);

  final String uri;
  final List<_ExportCombinator> combinators;
}

sealed class _ExportCombinator {
  const _ExportCombinator();
}

final class _Show extends _ExportCombinator {
  const _Show(this.names);

  final Set<String> names;
}

final class _Hide extends _ExportCombinator {
  const _Hide(this.names);

  final Set<String> names;
}
