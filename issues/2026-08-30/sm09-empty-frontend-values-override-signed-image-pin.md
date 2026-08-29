# Empty SM-09 frontend values override erases the signed image pin

## Problem

The private-registry harness writes an empty `envplane-frontend` YAML mapping.
Helm merges that null override over the umbrella parent values, exposing the
child chart's legacy frontend default instead of the signed immutable image.
The compatibility guard correctly fails the install.

## Required fix

Remove no-op null component mappings from the harness overlay so the packaged
umbrella's signed image values remain effective.
