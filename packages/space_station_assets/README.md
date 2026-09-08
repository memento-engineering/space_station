# space_station_assets

The reusable Dart composition behind memento's grid station. It provides the
`SpaceDelegate` station seed, resident `up`, `down`, and `status` commands, and
the composed asset, search, filing, approval, and operator command surfaces.
Downstream stations can import the package and extend the composition without
forking it.

## Install

```console
dart pub add space_station_assets
```

## Run a station

Stations are JIT Dart programs. A minimal `bin/space.dart` entrypoint is:

```dart
import 'dart:io';

import 'package:space_station_assets/space_station_assets.dart';

Future<void> main(List<String> arguments) async {
  final code = await buildRunner(
    environment: Platform.environment,
  ).run(arguments);
  if (code != null) exitCode = code;
}
```

Run it with `dart run your_package:space`.

## Extend the composition

Create a `SpaceDelegate` subclass to author a downstream station's identity,
state-store prefix, roster, environment posture, and work capabilities. Keep
its constructor compatible with `SpaceDelegateFactory`, then pass the
constructor tear-off to `buildRunner`:

```dart
final runner = buildRunner(
  name: 'lunar',
  description: 'lunar grid station',
  runnerInvocation: 'dart run lunar:lunar',
  delegateFactory: LunarDelegate.new,
  environment: Platform.environment,
)..addCommand(MyCommand());
```

Override only the station-owned values and compose additional commands on the
returned runner. The base package continues to supply the resident lifecycle,
status wire, and shared operator surfaces.
