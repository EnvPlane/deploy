# Anonymous multi-architecture pulls collide in the local Docker daemon

## Summary

The release gate anonymously pulls the same manifest-list digest for
`linux/amd64` and `linux/arm64`. Docker stores the first platform under the
digest reference and refuses to overwrite it with the second platform,
reporting `cannot overwrite digest`.

## Impact

All anonymous Helm pulls succeed, but the release stops during image
verification and never publishes its signed stable index.

## Expected fix

Remove each verified platform image from the disposable runner before pulling
the next platform. Keep both checks as real anonymous `docker pull` operations.
