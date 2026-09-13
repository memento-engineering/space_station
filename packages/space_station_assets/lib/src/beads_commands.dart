/// `space beads configure` — the OFFLINE operator verb that projects this
/// station's CODED roster into `bd`'s OWN cross-store primitive.
///
/// **The ruling** (Nico, 2026-09-13; the_grid
/// `docs/decisions/the-grid-is-a-beads-controller.md`): cross-store blocking
/// rides bd's native external dependency. `bd` resolves
/// `external:<project>:<capability>` through the per-store `external_projects`
/// map — `{name: path}` read from a store's `.beads/config.yaml` with
/// `.beads/config.local.yaml` merged on top (bd `internal/config`:
/// `GetExternalProjects` / `ResolveExternalProjectPath`). No store in this
/// station's roster carries that map, so every `external:` row an operator
/// writes is dead on arrival and the resident REFUSES it.
///
/// **The station adds nothing bd lacks.** This verb writes bd's own config key
/// from the ONE authority on which projects exist — [SpaceDelegate.substations],
/// read through the owned offline mount ([codedRosterOf]: construct → mount →
/// dispose), never the resident. It invents no dependency model, no link bead,
/// and no second roster.
///
/// **Where it writes.** `config.local.yaml` only: the resolved roots are THIS
/// machine's absolute paths, so they are machine-local and the tracked
/// `config.yaml` is left untouched. Every unrelated key in the local file
/// survives the write — the file belongs to the operator, and this verb owns
/// exactly one key in it.
///
/// **Idempotent.** The projection is compared against the map already in the
/// file; an equal map is reported `unchanged` and NOTHING is written, so a
/// second run leaves every file byte-identical. `--dry-run` prints the map per
/// store and writes nothing at all.
///
/// **A substation with no store is reported and skipped, never created.** A
/// root without a `.beads/` directory is not a bd store; minting one here would
/// invent a store the station never authored.
///
/// **bd merges the local file only over a primary one.** bd reads
/// `config.local.yaml` as an OVERLAY on `config.yaml` and skips the overlay
/// entirely when the store has no `config.yaml` (bd `internal/config`: the
/// local merge runs inside the `configPaths` branch). Every `bd init` store has
/// one, so this is not a case worth branching on — but a hand-made `.beads/`
/// with no `config.yaml` will take the write and bd will still not read it.
library;

import 'dart:io';

import 'package:args/command_runner.dart' show Command, UsageException;
import 'package:grid_sdk/grid_sdk.dart'
    show SubstationScope, SubstationScopeStores;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart' show YamlException, loadYaml;
import 'package:yaml_edit/yaml_edit.dart' show YamlEditor;

import 'space_delegate.dart';

/// bd's cross-project resolution key — the ONE key this verb owns in a store's
/// local config (bd `internal/config`: `GetExternalProjects`).
const String kExternalProjectsKey = 'external_projects';

/// The machine-local half of a bd store's config, merged over `config.yaml`
/// by bd itself. The projected roots are absolute paths on THIS machine, so
/// they never belong in the tracked file.
const String kLocalConfigFileName = 'config.local.yaml';

/// What `beads configure` did — or refused to do — for ONE substation store.
sealed class BeadsConfigureOutcome {
  /// Names the substation and the root its store is expected at.
  const BeadsConfigureOutcome({required this.name, required this.root});

  /// The coded substation's name — the key OTHER stores resolve it by.
  final String name;

  /// The substation's resolved (absolute) root.
  final String root;
}

/// The store's `external_projects` map differed and was rewritten — or, under
/// `--dry-run`, WOULD be rewritten.
final class ExternalProjectsWritten extends BeadsConfigureOutcome {
  /// Records the [projects] projected into the local config at [configPath].
  const ExternalProjectsWritten({
    required super.name,
    required super.root,
    required this.configPath,
    required this.projects,
  });

  /// The `.beads/config.local.yaml` path the projection lands in.
  final String configPath;

  /// The projected map: every OTHER coded substation, name → absolute root.
  final Map<String, String> projects;
}

/// The store already carried exactly this map; nothing was written.
final class ExternalProjectsUnchanged extends BeadsConfigureOutcome {
  /// Records the already-current [projects] at [configPath].
  const ExternalProjectsUnchanged({
    required super.name,
    required super.root,
    required this.configPath,
    required this.projects,
  });

  /// The `.beads/config.local.yaml` path that already carries the projection.
  final String configPath;

  /// The map the file already holds — identical to the projection.
  final Map<String, String> projects;
}

/// The substation's root holds no `.beads/` directory: reported and skipped,
/// never created.
final class WorkStoreMissing extends BeadsConfigureOutcome {
  /// Records the absent store directory [beadsDir].
  const WorkStoreMissing({
    required super.name,
    required super.root,
    required this.beadsDir,
  });

  /// The store directory that does not exist.
  final String beadsDir;

  /// A short refusal reason rendered verbatim after a `skipped` line.
  String get reason => 'no store at $beadsDir';
}

/// The store's existing local config cannot be edited without guessing at the
/// operator's data, so it is REFUSED rather than clobbered.
final class LocalConfigRefused extends BeadsConfigureOutcome {
  /// Records why [configPath] was left untouched.
  const LocalConfigRefused({
    required super.name,
    required super.root,
    required this.configPath,
    required this.reason,
  });

  /// The local config this verb refused to rewrite.
  final String configPath;

  /// The refusal, stated in the operator's terms.
  final String reason;
}

/// The external-projects map store [name] gets: every OTHER substation in
/// [roster], by coded name, mapped to its resolved absolute root.
///
/// Sorted by name so the written file is deterministic — a re-run over the same
/// roster must produce byte-identical output, which is what makes the
/// `unchanged` report meaningful.
Map<String, String> externalProjectsFor({
  required String name,
  required List<SubstationScope> roster,
}) {
  final others = [
    for (final scope in roster)
      if (scope.name != name) scope,
  ]..sort((a, b) => a.name.compareTo(b.name));
  return {for (final scope in others) scope.name: scope.root};
}

/// Projects a coded roster into each substation store's bd `external_projects`
/// map.
///
/// Stateless: the roster is handed in (the caller owns the offline mount) and
/// the only state touched is each store's `config.local.yaml`.
class BeadsConfigureService {
  /// Creates the projection service.
  const BeadsConfigureService();

  /// Projects [roster] into every substation store, in roster order.
  ///
  /// With [dryRun] true nothing is written; the outcomes still report exactly
  /// what a live run would do, so the printed map is the map that would land.
  List<BeadsConfigureOutcome> configure({
    required List<SubstationScope> roster,
    bool dryRun = false,
  }) => [
    for (final scope in roster) _configureOne(scope, roster, dryRun: dryRun),
  ];

  BeadsConfigureOutcome _configureOne(
    SubstationScope scope,
    List<SubstationScope> roster, {
    required bool dryRun,
  }) {
    final beadsDir = scope.workStore.beadsDir;
    if (!Directory(beadsDir).existsSync()) {
      return WorkStoreMissing(
        name: scope.name,
        root: scope.root,
        beadsDir: beadsDir,
      );
    }
    final configPath = p.join(beadsDir, kLocalConfigFileName);
    final projects = externalProjectsFor(name: scope.name, roster: roster);
    final file = File(configPath);
    final existingText = file.existsSync() ? file.readAsStringSync() : '';

    final Object? document;
    try {
      document = existingText.trim().isEmpty ? null : loadYaml(existingText);
    } on YamlException catch (error) {
      return LocalConfigRefused(
        name: scope.name,
        root: scope.root,
        configPath: configPath,
        reason: 'the file is not valid YAML (${error.message})',
      );
    }
    if (document != null && document is! Map) {
      return LocalConfigRefused(
        name: scope.name,
        root: scope.root,
        configPath: configPath,
        reason:
            'the document is a ${document.runtimeType}, not a mapping — a bd '
            'config is a mapping of keys',
      );
    }
    final existingNode = document is Map
        ? document[kExternalProjectsKey]
        : null;
    if (existingNode != null && existingNode is! Map) {
      return LocalConfigRefused(
        name: scope.name,
        root: scope.root,
        configPath: configPath,
        reason:
            '$kExternalProjectsKey is a ${existingNode.runtimeType}, not a '
            'mapping of project names to paths',
      );
    }
    final existing = <String, String>{
      if (existingNode is Map)
        for (final entry in existingNode.entries)
          '${entry.key}': '${entry.value}',
    };
    if (_sameProjects(existing, projects)) {
      return ExternalProjectsUnchanged(
        name: scope.name,
        root: scope.root,
        configPath: configPath,
        projects: projects,
      );
    }
    if (!dryRun) {
      file.writeAsStringSync(
        _rendered(
          existingText: existingText,
          hasKey: existingNode != null,
          projects: projects,
        ),
      );
    }
    return ExternalProjectsWritten(
      name: scope.name,
      root: scope.root,
      configPath: configPath,
      projects: projects,
    );
  }

  /// Rewrites ONLY [kExternalProjectsKey], preserving every other key, the
  /// comments, and the operator's formatting.
  ///
  /// `yaml_edit` can only update a key that exists, so a document without one
  /// is SEEDED with an empty `external_projects:` entry appended at the end
  /// before the update runs. Seeding by append (rather than letting the editor
  /// insert) keeps an operator's existing keys and header comments where they
  /// were.
  String _rendered({
    required String existingText,
    required bool hasKey,
    required Map<String, String> projects,
  }) {
    final base = hasKey ? existingText : _seeded(existingText);
    final editor = YamlEditor(base)..update([kExternalProjectsKey], projects);
    final rendered = editor.toString();
    return rendered.endsWith('\n') ? rendered : '$rendered\n';
  }

  String _seeded(String existingText) {
    if (existingText.isEmpty) return '$kExternalProjectsKey:\n';
    final separator = existingText.endsWith('\n') ? '' : '\n';
    return '$existingText$separator$kExternalProjectsKey:\n';
  }

  bool _sameProjects(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}

/// `space beads` — the operator's bd-store group.
class BeadsCommand extends Command<int> {
  /// Composes the group over its [configure] subcommand.
  BeadsCommand({required BeadsConfigureCommand configure}) {
    addSubcommand(configure);
  }

  @override
  final String name = 'beads';

  @override
  final String description =
      "Operate the bd stores this station's roster names.";
}

/// `space beads configure` — writes the coded roster into every substation
/// store's bd `external_projects` map.
class BeadsConfigureCommand extends Command<int> {
  /// Builds the verb over the roster [delegateFactory] authors.
  ///
  /// [gridHomeDefault] resolves the home used when `--grid-home` is absent
  /// (the real CWD; tests inject a fixture home). [service] is the projection
  /// (tests drive it directly over temp roots). [out]/[err] default to the
  /// process sinks.
  BeadsConfigureCommand({
    String Function() gridHomeDefault = _currentDirectory,
    SpaceDelegateFactory delegateFactory = SpaceDelegate.new,
    BeadsConfigureService service = const BeadsConfigureService(),
    StringSink? out,
    StringSink? err,
  }) : _gridHomeDefault = gridHomeDefault,
       _delegateFactory = delegateFactory,
       _service = service,
       _out = out ?? stdout,
       _err = err ?? stderr {
    argParser
      ..addOption(
        'grid-home',
        help:
            'The grid home the coded roster resolves its substation roots '
            'against. Must be ABSOLUTE. Defaults to the current directory.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help:
            'Print the map each store would get and write nothing. The '
            'written-vs-unchanged report is the same one a live run makes.',
      );
  }

  final String Function() _gridHomeDefault;
  final SpaceDelegateFactory _delegateFactory;
  final BeadsConfigureService _service;
  final StringSink _out;
  final StringSink _err;

  @override
  final String name = 'configure';

  @override
  final String description =
      "Project the coded roster into every substation store's bd "
      'external_projects map (.beads/config.local.yaml), so '
      'external:<substation>:<capability> dependencies resolve. Offline and '
      'idempotent: config.yaml is never touched, unrelated local keys survive, '
      'and a substation root with no .beads store is skipped, never created.';

  @override
  Future<int> run() async {
    final flag = argResults?.option('grid-home')?.trim();
    final home = flag == null || flag.isEmpty ? _gridHomeDefault() : flag;
    if (!p.isAbsolute(home)) {
      throw UsageException(
        'beads configure: --grid-home "$home" is relative. The coded roster '
        'resolves its ../<repo> substation roots against the home and WRITES '
        'those resolved paths into each store, so an ambiguously rooted home '
        'would bake this process\'s cwd into another repo\'s config.',
        usage,
      );
    }
    final dryRun = argResults?.flag('dry-run') ?? false;
    final roster = codedRosterOf(_delegateFactory, gridRoot: home);
    final outcomes = _service.configure(roster: roster, dryRun: dryRun);
    if (dryRun) {
      _out.writeln('beads configure: DRY-RUN, nothing is written.');
    }
    var refused = false;
    for (final outcome in outcomes) {
      switch (outcome) {
        case ExternalProjectsWritten(:final name, :final projects):
          _out.writeln(
            '$name -> ${projects.length} projects '
            '${dryRun ? 'to write' : 'written'}',
          );
          if (dryRun) _writeMap(projects);
        case ExternalProjectsUnchanged(:final name, :final projects):
          _out.writeln('$name -> ${projects.length} projects unchanged');
          if (dryRun) _writeMap(projects);
        case WorkStoreMissing(:final name, :final reason):
          _out.writeln('$name -> skipped ($reason)');
        case LocalConfigRefused(:final name, :final configPath, :final reason):
          refused = true;
          _err.writeln('$name -> REFUSED $configPath: $reason');
      }
    }
    return refused ? 1 : 0;
  }

  void _writeMap(Map<String, String> projects) {
    for (final entry in projects.entries) {
      _out.writeln('    ${entry.key}: ${entry.value}');
    }
  }
}

/// Builds `beads` composed with the roster [delegateFactory] authors.
///
/// [gridHomeDefault], [service], [out] and [err] are the same seams
/// [BeadsConfigureCommand] takes; a downstream station composes this exactly as
/// space does, passing ITS delegate tear-off.
BeadsCommand buildSpaceBeadsCommand({
  String Function() gridHomeDefault = _currentDirectory,
  SpaceDelegateFactory delegateFactory = SpaceDelegate.new,
  BeadsConfigureService service = const BeadsConfigureService(),
  StringSink? out,
  StringSink? err,
}) => BeadsCommand(
  configure: BeadsConfigureCommand(
    gridHomeDefault: gridHomeDefault,
    delegateFactory: delegateFactory,
    service: service,
    out: out,
    err: err,
  ),
);

String _currentDirectory() => Directory.current.absolute.path;
