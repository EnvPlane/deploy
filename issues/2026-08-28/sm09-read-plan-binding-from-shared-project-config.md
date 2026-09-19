# SM-09 read a per-environment plan from shared project config

## Status

Fixed.

## Problem

The live harness tried to discover the Secret materialization plan through the
shared compiled project config. The binding is environment-specific and only
existed in a transient runtime copy, so a clean production deployment stopped
after environment creation when the expected field was absent.

## Resolution

Read the redacted plan ID from the authenticated environment-scoped
materialization status endpoint. The harness no longer depends on mutating or
overloading immutable shared project configuration.
