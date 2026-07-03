/// memento's grid station — the assembled runner (the Dart runner model — see
/// the_grid `docs/SCRATCH-dart-runner-and-cli-sdk.md`).
///
/// A station is a user-composed, AOT-compiled runner: [buildRunner] assembles
/// the Commands memento wants — the generic CLI-SDK ones (watch/gate/demo and
/// serve/lease, "leasing is core") from `grid_cli`, plus the asset-exported
/// [DartCommand] from the DART domain, plus memento's OWN resident verbs
/// (RS-5b, `the_grid/docs/SCRATCH-resident-station.md`): `up`/`down`/
/// `status` — the composed resident station + its thin attach client (RS-8
/// retired the transitional `run`/`CodeRunCommand` once `up` proved out).
/// `bin/space.dart` runs it; `dart compile exe bin/space.dart -o space` ships
/// it. The construction lives here in the lib (not on the bin) so a test — or
/// a Flutter app — can build the runner without running it.
library;

import 'package:args/command_runner.dart';
import 'package:dart_grid_assets/dart_grid_assets.dart' show DartCommand;
import 'package:grid_assets/grid_assets.dart'
    show
        CommandResult,
        ComputeBounds,
        DispatchCommand,
        computeDispatchHandler,
        kComputeKind;
import 'package:grid_cli/grid_cli.dart'
    show DemoCommand, GateCommand, LeaseCommand, ServeCommand, WatchCommand;

import 'src/down_command.dart';
import 'src/status_command.dart';
import 'src/up_command.dart';

/// Builds memento's `space` [CommandRunner]: the generic CLI-SDK commands plus
/// the power_station assets' exported Commands, with the COMPUTE asset's use
/// (bounded dispatch + its payload/result codec) assembled into the generic
/// serve/lease commands — the asset owns the "use" (ADR-0011 D3).
CommandRunner<int> buildRunner() =>
    CommandRunner<int>('space', "memento's grid station")
      ..addCommand(WatchCommand())
      // memento's OWN resident verbs (RS-5b): the composed resident station
      // (up) + the thin StationAttach renders over it (down/status).
      ..addCommand(UpCommand())
      ..addCommand(DownCommand())
      ..addCommand(StatusCommand())
      // The butane burn is TEMPORARILY decomposed (2026-07-02): the pack lives
      // in gc-owned butane_flutter, which is not yet migrated onto the Circuit
      // rename (the_grid #10 / power_station #4) — recompose `BurnRunCommand()`
      // when butane_grid_assets migrates (butane integration is deprioritized
      // per Nico's policy; the pack stays with its domain).
      // Asset-exported Commands consumed by a runner (the CLI-SDK model): the
      // DART domain ships DartCommand from dart_grid_assets; this app just
      // assembles it.
      ..addCommand(DartCommand())
      ..addCommand(GateCommand())
      ..addCommand(DemoCommand())
      // serve/lease are GENERIC core commands ("leasing is core"); the
      // COMPUTE asset's use (bounded dispatch + its payload/result codec) is
      // assembled in here — the asset owns the "use" (ADR-0011 D3).
      ..addCommand(
        ServeCommand(
          defaultKind: kComputeKind,
          configureFlags: (parser) => parser
            ..addMultiOption(
              'allow',
              defaultsTo: const [
                'dart',
                'echo',
                'flutter',
                'git',
                'hostname',
                'melos',
                'uname',
              ],
              help:
                  'The executables the lessor will run (the bounded-use '
                  'allow-list). A dispatched command not on this list is '
                  'REFUSED (no shell-as-a-service; ADR-0011 RCE-bounds).',
            )
            ..addOption(
              'exec-timeout',
              defaultsTo: '300',
              help:
                  'Per-command timeout in seconds (the bounded-use upper '
                  'bound).',
            ),
          handlerFor: (args, log) {
            final bounds = ComputeBounds(
              allowedCommands: args.multiOption('allow').toSet(),
              timeout: Duration(
                seconds: int.parse(args.option('exec-timeout')!),
              ),
            );
            return (
              handler: computeDispatchHandler(bounds: bounds, onLog: log),
              banner:
                  'bounded use: allow-list '
                  '${bounds.allowedCommands.toList()..sort()}  ·  '
                  'timeout ${bounds.timeout.inSeconds}s',
              // Compute launches nothing that outlives a dispatch — no
              // lease-end teardown (the burn's lessor, by contrast, reaps
              // its follower app here).
              onLeaseEnded: null,
            );
          },
        ),
      )
      ..addCommand(
        LeaseCommand(
          defaultKind: kComputeKind,
          payloadFor: (rest) => DispatchCommand(
            command: rest.first,
            args: rest.skip(1).toList(),
          ).toJson(),
          render: (raw, out, err) {
            final r = CommandResult.fromJson(raw);
            if (r.stdout.isNotEmpty) out(r.stdout);
            if (r.stderr.isNotEmpty) err(r.stderr);
            return r.exitCode;
          },
        ),
      );
