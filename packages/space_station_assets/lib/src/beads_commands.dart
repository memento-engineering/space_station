/// `space beads configure` — the OFFLINE operator verb that projects this
/// station's CODED roster into `bd`'s OWN cross-store primitive.
///
/// **The ruling** (Nico, 2026-09-13; the_grid
/// `docs/decisions/the-grid-is-a-beads-controller.md`): cross-store blocking
/// rides bd's native external dependency. `bd` places
/// `external:<project>:<capability>` through the per-store `external_projects`
/// map — `{name: path}` read from a store's `.beads/config.yaml` with
/// `.beads/config.local.yaml` merged on top. No store in this station's roster
/// carries that map, so every `external:` row an operator writes names a
/// project nothing can place, and the resident REFUSES it.
///
/// **What the installed bd does with the map, MEASURED** (HEAD-a45199a, the
/// fleet build; receipts in `test/beads_configure_bd_test.dart`): it reads the
/// merged config and reports the projected projects (`bd config show --json`),
/// and it accepts and stores an `external:` edge on the issue record. It does
/// NOT yet subtract that edge as a blocker at query time — `bd dep list`,
/// `bd blocked` and `bd ready` ignore it, configured project or not. Honouring
/// the row in the frontier is the grid's, not this verb's (`tg-xh5d`), and the
/// governor's ruling of 2026-09-13 scopes this bead to the projection: the map
/// bd reads, written from the one authority on which projects exist.
///
/// **The station adds nothing bd lacks.** This verb writes bd's own config key
/// from the ONE authority on which projects exist — [SpaceDelegate.substations],
/// read through the owned offline mount ([codedRosterOf]: construct → mount →
/// dispose), never the resident. It invents no dependency model, no link bead,
/// and no second roster.
///
/// **ARMED is the unit, and armed is not this verb's own word.** The roster
/// names substations; a substation is ARMED when its root resolves a `.beads/`
/// work store, which is exactly what `space up` arms the tree with (grid_sdk
/// [StoreLocator.locateWorkStore], the same probe, the same refusal). Only
/// armed substations are written, and only armed substations appear in the map
/// a store is written — an unarmed root is not a project any store can resolve
/// a dependency into, so projecting it would write a row pointing at nothing.
///
/// **Where it writes.** `config.local.yaml` only: the resolved roots are THIS
/// machine's absolute paths, so they are machine-local and the tracked
/// `config.yaml` is left untouched. Every unrelated key in the local file
/// survives the write — the file belongs to the operator, and this verb owns
/// exactly one key in it.
///
/// **And it makes that file IGNORED.** Machine-local is only half a promise
/// while git can still see the file: a projected config carries THIS machine's
/// absolute paths, and a `git add -A` in a substation repo would commit them.
/// bd's own `.beads/.gitignore` carries no pattern for `config.local.yaml`
/// (measured on every store in this station's roster), so the verb appends one
/// — the exact line, under a comment naming the verb — to the store's
/// `.beads/.gitignore`, creating that file only when the store has none. A
/// store that already ignores the file is left byte-identical, which is what
/// keeps a second run a no-op; and no NEGATION is ever written, because bd's
/// own file warns that one would override the fork protection in
/// `.git/info/exclude`.
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
/// **bd merges the local file only over a primary one, so a store with no
/// `config.yaml` is ALSO skipped.** bd reads `config.local.yaml` as an OVERLAY
/// on `config.yaml` and skips the overlay entirely when the store has no
/// `config.yaml`. Writing one there would be INERT — the verb would report a
/// projection bd never reads — so the store is reported `skipped` instead, and
/// the missing `config.yaml` is never invented either. Every `bd init` store
/// has one, so this is the hand-made `.beads/` case.
///
/// **Nothing here is written blind.** An existing local config that cannot be
/// rewritten without guessing at the operator's data is REFUSED per store
/// (stderr, exit 1) and left byte-identical, and the rest of the roster is
/// still configured: no parse or rewrite failure aborts the run half-done. A
/// refused store keeps its `.gitignore` too — the file the verb refused to
/// touch holds the OPERATOR's data, not this machine's projected paths, so the
/// whole store is left exactly as it was found rather than half-acted-on.
library;

import 'dart:io';

import 'package:args/command_runner.dart' show Command, UsageException;
import 'package:grid_sdk/grid_sdk.dart'
    show StoreLocator, StoreRefusal, SubstationScope, SubstationScopeStores;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart' show YamlException, loadYaml;
import 'package:yaml_edit/yaml_edit.dart' show YamlEditor;

import 'space_delegate.dart';

/// bd's cross-project resolution key — the ONE key this verb owns in a store's
/// local config.
const String kExternalProjectsKey = 'external_projects';

/// The machine-local half of a bd store's config, merged over
/// [kPrimaryConfigFileName] by bd itself. The projected roots are absolute
/// paths on THIS machine, so they never belong in the tracked file.
const String kLocalConfigFileName = 'config.local.yaml';

/// The TRACKED half of a bd store's config. This verb never writes it, and bd
/// reads [kLocalConfigFileName] only as an overlay on one, so a store without
/// it is skipped rather than given an inert projection.
const String kPrimaryConfigFileName = 'config.yaml';

/// The store-local git ignore file bd itself ships in every `bd init` store.
/// This verb appends exactly one pattern to it — [kLocalConfigFileName] — so
/// the machine-local projection cannot be committed into a substation's repo.
const String kStoreIgnoreFileName = '.gitignore';

/// What the verb did about [kLocalConfigFileName] being git-ignored in ONE
/// store. Reported per store so the operator sees the repo-visible change the
/// verb made beyond the config itself.
enum LocalConfigIgnore {
  /// The store's [kStoreIgnoreFileName] already matched [kLocalConfigFileName]
  /// as an exact line, so nothing was written and the file is byte-identical.
  alreadyIgnored,

  /// The pattern was absent and this run appended it (creating
  /// [kStoreIgnoreFileName] only if the store had none). Under `--dry-run` it
  /// is what the run WOULD have appended; nothing is written.
  appended,
}

/// The stanza appended to a store's [kStoreIgnoreFileName]: the verb names
/// itself, then the one pattern it owns. Never a negation — bd's own file
/// warns that a negation here overrides the fork protection in
/// `.git/info/exclude`.
const String kLocalConfigIgnoreStanza =
    '# Machine-local bd config, written by `beads configure`: the\n'
    '# external_projects map holds THIS machine\'s absolute paths.\n'
    '$kLocalConfigFileName\n';

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
  /// Records the [projects] projected into the local config at [configPath],
  /// and how [ignore] left the store's git ignore.
  const ExternalProjectsWritten({
    required super.name,
    required super.root,
    required this.configPath,
    required this.projects,
    required this.ignore,
  });

  /// The `.beads/config.local.yaml` path the projection lands in.
  final String configPath;

  /// The projected map: every OTHER ARMED substation, name → absolute root.
  final Map<String, String> projects;

  /// Whether the store already ignored the local config, or this run appended
  /// the pattern to its `.beads/.gitignore`.
  final LocalConfigIgnore ignore;
}

/// The store already carried exactly this map; nothing was written.
final class ExternalProjectsUnchanged extends BeadsConfigureOutcome {
  /// Records the already-current [projects] at [configPath], and how [ignore]
  /// left the store's git ignore — an unchanged projection can still need the
  /// ignore appended, since the two are separate files.
  const ExternalProjectsUnchanged({
    required super.name,
    required super.root,
    required this.configPath,
    required this.projects,
    required this.ignore,
  });

  /// The `.beads/config.local.yaml` path that already carries the projection.
  final String configPath;

  /// The map the file already holds — identical to the projection.
  final Map<String, String> projects;

  /// Whether the store already ignored the local config, or this run appended
  /// the pattern to its `.beads/.gitignore`.
  final LocalConfigIgnore ignore;
}

/// The substation's root holds no `.beads/` work store: it is NOT armed, so it
/// is reported and skipped, never created — and it is no project either.
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

/// The store exists but carries no tracked [kPrimaryConfigFileName], so bd
/// would never read a [kLocalConfigFileName] beside it. The write would be
/// inert, so it is reported and skipped — and the tracked config is not
/// invented here either.
final class PrimaryConfigMissing extends BeadsConfigureOutcome {
  /// Records the absent tracked config at [primaryConfigPath].
  const PrimaryConfigMissing({
    required super.name,
    required super.root,
    required this.primaryConfigPath,
  });

  /// The tracked `config.yaml` bd would have merged the projection over.
  final String primaryConfigPath;

  /// A short refusal reason rendered verbatim after a `skipped` line.
  String get reason =>
      'no $kPrimaryConfigFileName at $primaryConfigPath, so bd would never '
      'read a $kLocalConfigFileName beside it';
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
/// [armed], by coded name, mapped to its resolved absolute root.
///
/// [armed] is the ARMED roster — the substations whose roots resolve a work
/// store. An unarmed substation is not a project: bd would resolve the name to
/// a directory holding no store, so the row would be dead the moment a
/// dependency used it.
///
/// Sorted by name so the written file is deterministic — a re-run over the same
/// roster must produce byte-identical output, which is what makes the
/// `unchanged` report meaningful.
Map<String, String> externalProjectsFor({
  required String name,
  required List<SubstationScope> armed,
}) {
  final others = [
    for (final scope in armed)
      if (scope.name != name) scope,
  ]..sort((a, b) => a.name.compareTo(b.name));
  return {for (final scope in others) scope.name: scope.root};
}

/// Projects a coded roster into every ARMED substation store's bd
/// `external_projects` map.
///
/// Stateless: the roster is handed in (the caller owns the offline mount) and
/// the only state touched is each store's `config.local.yaml`.
class BeadsConfigureService {
  /// Creates the projection service.
  const BeadsConfigureService();

  /// Projects [roster] into every ARMED substation store, in roster order.
  ///
  /// Armed is decided ONCE, up front, with grid_sdk's own
  /// [StoreLocator.locateWorkStore] — the probe `space up` arms with — so the
  /// map every store gets and the set of stores written come from the same
  /// answer. With [dryRun] true nothing is written; the outcomes still report
  /// exactly what a live run would do, so the printed map is the map that would
  /// land.
  List<BeadsConfigureOutcome> configure({
    required List<SubstationScope> roster,
    bool dryRun = false,
  }) {
    final locator = StoreLocator();
    final armed = <SubstationScope>[
      for (final scope in roster)
        if (_isArmed(locator, scope)) scope,
    ];
    final armedNames = <String>{for (final scope in armed) scope.name};
    return [
      for (final scope in roster)
        if (armedNames.contains(scope.name))
          _configureArmed(scope, armed, dryRun: dryRun)
        else
          WorkStoreMissing(
            name: scope.name,
            root: scope.root,
            beadsDir: scope.workStore.beadsDir,
          ),
    ];
  }

  bool _isArmed(StoreLocator locator, SubstationScope scope) {
    try {
      locator.locateWorkStore(root: scope.root, substationName: scope.name);
      return true;
    } on StoreRefusal {
      return false;
    }
  }

  BeadsConfigureOutcome _configureArmed(
    SubstationScope scope,
    List<SubstationScope> armed, {
    required bool dryRun,
  }) {
    final beadsDir = scope.workStore.beadsDir;
    final primaryConfigPath = p.join(beadsDir, kPrimaryConfigFileName);
    if (!File(primaryConfigPath).existsSync()) {
      return PrimaryConfigMissing(
        name: scope.name,
        root: scope.root,
        primaryConfigPath: primaryConfigPath,
      );
    }
    final configPath = p.join(beadsDir, kLocalConfigFileName);
    final projects = externalProjectsFor(name: scope.name, armed: armed);
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
    // PRESENT-BUT-NULL is a key, not an absence: `external_projects:` with
    // nothing under it is what a half-finished hand edit leaves, and treating
    // it as absent would append a SECOND top-level key and make the document
    // unparseable. `containsKey` is the only question that separates the two.
    final hasKey =
        document is Map && document.containsKey(kExternalProjectsKey);
    final existingNode = hasKey ? document[kExternalProjectsKey] : null;
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
      // The projection is current, but the IGNORE is a second file: a store
      // configured before this verb owned the pattern (or one whose operator
      // dropped it) still needs it, and appending it is not a config rewrite.
      return ExternalProjectsUnchanged(
        name: scope.name,
        root: scope.root,
        configPath: configPath,
        projects: projects,
        ignore: _ensureIgnored(beadsDir, dryRun: dryRun),
      );
    }
    // Rendered BEFORE the dry-run branch and inside the guard: a rewrite this
    // verb cannot perform is a per-store refusal a dry run must also report,
    // and never an exception that strands the rest of the roster unconfigured.
    final String rendered;
    try {
      rendered = _rendered(
        existingText: existingText,
        hasKey: hasKey,
        projects: projects,
      );
    } on YamlException catch (error) {
      return LocalConfigRefused(
        name: scope.name,
        root: scope.root,
        configPath: configPath,
        reason: 'the rewritten document would not parse (${error.message})',
      );
    }
    // Ignored FIRST, then written: a projection of this machine's absolute
    // paths is never on disk in a state git can see it.
    final ignore = _ensureIgnored(beadsDir, dryRun: dryRun);
    if (!dryRun) file.writeAsStringSync(rendered);
    return ExternalProjectsWritten(
      name: scope.name,
      root: scope.root,
      configPath: configPath,
      projects: projects,
      ignore: ignore,
    );
  }

  /// Makes [kLocalConfigFileName] git-ignored in the store at [beadsDir], and
  /// says which of [LocalConfigIgnore] it was.
  ///
  /// The pattern is matched as an EXACT line (a leading `/` allowed — git reads
  /// `/config.local.yaml` in a `.beads/.gitignore` as the same path), so an
  /// already-ignored store is never appended to twice and a second run leaves
  /// the file byte-identical. Nothing else in the file is read, reordered or
  /// rewritten: the verb owns one line in it. A store with no
  /// [kStoreIgnoreFileName] gets one holding just this verb's stanza.
  LocalConfigIgnore _ensureIgnored(String beadsDir, {required bool dryRun}) {
    final ignoreFile = File(p.join(beadsDir, kStoreIgnoreFileName));
    final existing = ignoreFile.existsSync()
        ? ignoreFile.readAsStringSync()
        : '';
    final ignored = existing
        .split('\n')
        .map((line) => line.trim())
        .any(
          (line) =>
              line == kLocalConfigFileName || line == '/$kLocalConfigFileName',
        );
    if (ignored) return LocalConfigIgnore.alreadyIgnored;
    if (!dryRun) {
      final separator = switch (existing) {
        '' => '',
        final text when text.endsWith('\n') => '\n',
        _ => '\n\n',
      };
      ignoreFile.writeAsStringSync(
        '$existing$separator$kLocalConfigIgnoreStanza',
      );
    }
    return LocalConfigIgnore.appended;
  }

  /// Rewrites ONLY [kExternalProjectsKey], preserving every other key, the
  /// comments, and the operator's formatting.
  ///
  /// `yaml_edit` can only update a key that exists, so a document without one
  /// is SEEDED with an empty `external_projects:` entry appended at the end
  /// before the update runs. Seeding by append (rather than letting the editor
  /// insert) keeps an operator's existing keys and header comments where they
  /// were. [hasKey] must come from `containsKey`: seeding over a present key
  /// whose value is null would duplicate it.
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

/// `space beads configure` — writes the ARMED roster into every armed
/// substation store's bd `external_projects` map.
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
      "Project the ARMED roster into every armed substation store's bd "
      'external_projects map (.beads/config.local.yaml), so an '
      'external:<substation>:<capability> dependency names a project bd can '
      'place. Offline and idempotent: config.yaml is never touched, unrelated '
      'local keys survive, the local config is added to the store\'s '
      '.beads/.gitignore, and a substation root with no .beads store is '
      'skipped, never created.';

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
        case ExternalProjectsWritten(
          :final name,
          :final projects,
          :final ignore,
        ):
          _out.writeln(
            '$name -> ${projects.length} projects '
            '${dryRun ? 'to write' : 'written'}'
            '${_ignoreSuffix(ignore, dryRun: dryRun)}',
          );
          if (dryRun) _writeMap(projects);
        case ExternalProjectsUnchanged(
          :final name,
          :final projects,
          :final ignore,
        ):
          _out.writeln(
            '$name -> ${projects.length} projects unchanged'
            '${_ignoreSuffix(ignore, dryRun: dryRun)}',
          );
          if (dryRun) _writeMap(projects);
        case WorkStoreMissing(:final name, :final reason):
          _out.writeln('$name -> skipped ($reason)');
        case PrimaryConfigMissing(:final name, :final reason):
          _out.writeln('$name -> skipped ($reason)');
        case LocalConfigRefused(:final name, :final configPath, :final reason):
          refused = true;
          _err.writeln('$name -> REFUSED $configPath: $reason');
      }
    }
    return refused ? 1 : 0;
  }

  /// Names the repo-visible half of the write, and only when there is one: an
  /// already-ignored store says nothing, so the common re-run stays quiet.
  String _ignoreSuffix(LocalConfigIgnore ignore, {required bool dryRun}) =>
      switch (ignore) {
        LocalConfigIgnore.alreadyIgnored => '',
        LocalConfigIgnore.appended =>
          dryRun
              ? ', $kLocalConfigFileName to ignore'
              : ', $kLocalConfigFileName ignored',
      };

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
