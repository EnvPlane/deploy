# Release-gate App owner literal violates the brand guard

## Problem

The compatible-source checkout authentication added a literal organization name
to a workflow environment variable. The repository brand guard rejects new
human-readable product branding in source files.

## Required fix

Derive the App owner from the GitHub workflow context while retaining the
cross-repository read-token behavior.
