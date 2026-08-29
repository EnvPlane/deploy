# Self-service chart changes did not bump child versions

The EP-SSO zero-values work changed the Agent and control-plane chart sources
without incrementing their chart versions or rebuilding the umbrella's vendored
archives. Deploy CI correctly rejected both stale versions and archive drift,
so the signed release index workflow could not run.

Bump both child chart patch versions, update the umbrella dependency pins, and
rebuild the vendored dependency lock and archives.
