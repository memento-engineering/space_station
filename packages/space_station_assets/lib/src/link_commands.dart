library;

import 'dart:io';

import 'package:grid_cli/grid_cli.dart' show LinkCommand, LinkEndpointStore;
import 'package:grid_sdk/grid_sdk.dart' show SubstationScopeStores;

import 'space_delegate.dart';

/// Builds the vended `link` verb over the roster authored by [delegateFactory].
///
/// The endpoint carries BOTH tokens a cross-store row needs: the substation's
/// bead-id `prefix` (how an endpoint id resolves to a store) and its roster
/// `name` (the `<project>` token an `external:<project>:<capability>` row
/// carries, which bd resolves through its own `external_projects` config).
///
/// There is no `unlink` composition any more: grid_cli 0.6.0-dev.3 retired the
/// verb with the state-store link bead itself (the_grid#447). A cross-store
/// blocker is a bd dependency row, so it is removed with
/// `bd dep remove <from> external:<project>:<capability>` — or, the intended
/// path, it lifts on its own when the target ships.
LinkCommand buildSpaceLinkCommand({
  String? gridRoot,
  SpaceDelegateFactory delegateFactory = SpaceDelegate.new,
}) {
  final resolvedGridRoot = gridRoot ?? Directory.current.absolute.path;
  return LinkCommand(
    endpoints: [
      for (final scope in codedRosterOf(
        delegateFactory,
        gridRoot: resolvedGridRoot,
      ))
        LinkEndpointStore(
          name: scope.name,
          prefix: scope.prefix,
          store: scope.workStore,
        ),
    ],
  );
}
