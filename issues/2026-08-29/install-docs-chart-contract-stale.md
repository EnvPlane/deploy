# Installation documentation chart contract was stale

## Problem

The umbrella Go contract test required the retired
`<published-umbrella-version>` placeholder and advanced dependency-mode text in
the beginner installation guide. EP-SSO-006 replaced the placeholder with the
stable version from the signed release index and moved advanced topology to a
dedicated guide, so the publication workflow failed after the documentation
contract itself had passed.

## Required fix

Read the checked-in stable release index in the Go smoke test, require its exact
install command in the beginner guide, and validate advanced topics in the
advanced guide. Keep the upgrade check explicit about `--reset-values`.

## Resolution

Update the Go contract and installation wording together, then run the complete
umbrella Go test package and both shell documentation contracts.
