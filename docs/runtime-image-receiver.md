# Runtime image publication receiver

`.github/workflows/propose-runtime-image-update.yaml` is the only receiver for
`component-image-published` events. Component release workflows dispatch the
following payload to `envpilot/deploy`:

```json
{
  "component": "runner",
  "source_repository": "envpilot/runner",
  "source_revision": "<40 lowercase hex characters>",
  "repository": "ghcr.io/envpilot/runner",
  "tag": "sha-<40 lowercase hex characters>",
  "digest": "sha256:<64 lowercase hex characters>",
  "publication_id": "<component>:<source revision>:<digest>"
}
```

The receiver rejects unknown component/source pairs, non-immutable tags and
digests, and mismatched GHCR repositories. It logs in to GHCR with the
read-only workflow token and verifies that the immutable tag resolves to the
submitted manifest digest before changing the checkout.

Updates are applied to only the selected child image block in
`deploy/helm/envpilot/values.yaml` and the matching `imagePins` entry plus
image reference in the current `release/<umbrella-version>.yaml` manifest. The
old reference, new digest/tag and source commit are included in the bot PR.

All component events use one concurrency group and one refreshable branch,
`automation/runtime-image-pins`. This makes simultaneous publications a
serialized read/modify/test transaction instead of competing branches that can
silently lose a pin. The receiver does not dispatch another image event, so
its merge cannot create a workflow loop. Replaying the same publication is
safe because the updater converges on the same values and refreshes the
existing PR. Chart lint, dependency build and template rendering run before
the PR is created; the workflow then squash-merges that validated serialized
PR. A release accepts only a compatibility manifest whose `sourceRevision`
equals the current `deploy/main`, so it cannot silently publish a prior pin
set when a newer component publication was processed.
