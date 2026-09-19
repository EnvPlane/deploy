# SM-09 pre-created namespaces conflict with Helm ownership

## Problem

The private-registry harness creates the base and target namespaces before the
umbrella install so it can seed source Secrets. The enabled E2E fixture renders
those same Namespace resources. Helm refuses to adopt the pre-existing
namespaces because they do not carry this release's ownership metadata.

Failed run: [Publish latest compatible EnvPlane umbrella release run
32995369264](https://github.com/EnvPlane/deploy/actions/runs/32995369264).

## Resolution

Let the canonical umbrella E2E fixture create and own both namespaces. Seed the
registry and application source Secrets immediately after the successful Helm
install and before compiling or dispatching a materialization plan.

