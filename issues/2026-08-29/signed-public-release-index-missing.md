# Signed public release index is missing

The umbrella release publishes a signed OCI chart and machine-readable JSON,
but the JSON consumed by a public install landing has no independent signature.
The landing therefore cannot prove that its selected stable version, digest,
support matrix, install command, or first-run handoff came from the release
workflow.

Publish a versioned release index with a Sigstore bundle, validate its
credential-free schema in CI, and make both files immutable release assets.
