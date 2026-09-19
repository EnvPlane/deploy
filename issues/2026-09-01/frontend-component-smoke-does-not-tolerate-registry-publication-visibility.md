# Frontend component smoke does not tolerate registry publication visibility

The compatibility resolver retries the pinned frontend tag until GHCR returns
the expected index digest. The later component-repair smoke check made only
one lookup of the same tag. A transient registry or CDN visibility mismatch
therefore failed the release after the compatibility artifact had already been
confirmed.

The smoke must use the same bounded retry policy and, after resolving the tag,
pull the immutable `repository@digest` reference so a tag cannot change between
verification and content inspection.
