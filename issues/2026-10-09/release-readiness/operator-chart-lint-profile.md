# Operator-only chart requires an explicit lint profile

Deploy CI run 37901221228 failed because the all-chart loop linted envplane-finops-private with deliberately empty mandatory operator settings. Publication used the same loop.

Fix: share a canonical chart lint script and supply a render-only fixture for the private chart. Keep the strict schema and blank production defaults. The fixture uses reserved documentation addresses and nonexistent images and must never be installed.

Implementation prompt: lint every canonical chart, assert missing required private settings still fail validation, and run CI/publication without skipping any chart or relaxing production safety checks.
