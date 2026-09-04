library;

import 'dart:io';

import 'package:grid_cli/grid_cli.dart'
    show LinkCommand, LinkEndpointStore, UnlinkCommand;
import 'package:grid_sdk/grid_sdk.dart' show SubstationScopeStores;

import 'space_delegate.dart';

/// The vended cross-store authoring commands composed with this station roster.
typedef SpaceLinkCommands = ({LinkCommand link, UnlinkCommand unlink});

/// Builds `link` and `unlink` over the roster and state partition authored
/// by [delegateFactory].
SpaceLinkCommands buildSpaceLinkCommands({
  String? gridRoot,
  SpaceDelegateFactory delegateFactory = SpaceDelegate.new,
}) {
  final resolvedGridRoot = gridRoot ?? Directory.current.absolute.path;
  final stateStorePrefix = _stateStorePrefixOf(
    delegateFactory,
    gridRoot: resolvedGridRoot,
  );
  final endpoints = [
    for (final scope in codedRosterOf(
      delegateFactory,
      gridRoot: resolvedGridRoot,
    ))
      LinkEndpointStore(prefix: scope.prefix, store: scope.workStore),
  ];
  return (
    link: LinkCommand(stateStorePrefix: stateStorePrefix, endpoints: endpoints),
    unlink: UnlinkCommand(
      stateStorePrefix: stateStorePrefix,
      endpoints: endpoints,
    ),
  );
}

String _stateStorePrefixOf(
  SpaceDelegateFactory factory, {
  required String gridRoot,
}) {
  final delegate = factory(gridRoot: gridRoot);
  try {
    return delegate.stateStorePrefix;
  } finally {
    delegate.dispose();
  }
}
