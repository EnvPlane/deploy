# SM-09 activation license values miss the commercialization scope

The private-registry release gate wrote activation verification keys and a
zero-day grace period under `envplane-control-plane.license`. The child chart
only reads `envplane-control-plane.commercialization.license`, so both values
were silently ignored: the activation could not be verified and the default
14-day grace period remained in effect.

Nest the E2E license fixture beneath `commercialization.license` to render the
intended runtime environment variables.
