library;

import 'dart:io';

import 'package:grid_cli/grid_cli.dart'
    show LinkCommand, LinkEndpointStore, UnlinkCommand;
import 'package:grid_sdk/grid_sdk.dart' show SubstationScopeStores;

import 'space_delegate.dart';

/// The grid-state store prefix that owns cross-store link beads.
const kSpaceStateStorePrefix = 'houston';

/// The vended cross-store authoring commands composed with this station roster.
typedef SpaceLinkCommands = ({LinkCommand link, UnlinkCommand unlink});

/// Builds `link` and `unlink` over the roster authored by [delegateFactory].
SpaceLinkCommands buildSpaceLinkCommands({
  String? gridRoot,
  SpaceDelegateFactory delegateFactory = SpaceDelegate.new,
}) {
  final resolvedGridRoot = gridRoot ?? Directory.current.absolute.path;
  final endpoints = [
    for (final scope in codedRosterOf(
      delegateFactory,
      gridRoot: resolvedGridRoot,
    ))
      LinkEndpointStore(prefix: scope.prefix, store: scope.workStore),
  ];
  return (
    link: LinkCommand(
      stateStorePrefix: kSpaceStateStorePrefix,
      endpoints: endpoints,
    ),
    unlink: UnlinkCommand(
      stateStorePrefix: kSpaceStateStorePrefix,
      endpoints: endpoints,
    ),
  );
}
