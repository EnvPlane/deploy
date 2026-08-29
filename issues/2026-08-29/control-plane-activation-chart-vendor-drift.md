# Vendored control-plane chart omits activation verification settings

## Problem

The canonical control-plane chart now mounts activation verification metadata,
but the umbrella still vendors the older 0.3.44 archive. The vendored-chart
drift gate correctly blocks release publication.

## Required fix

Bump the changed child chart version, update the umbrella dependency and lock,
and rebuild the vendored archive from the canonical chart source.
