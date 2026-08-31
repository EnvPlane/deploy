# Zero-day license grace is overridden by the chart default

## Problem

The control-plane chart used Helm's `default` function for `license.graceDays`.
Helm treats `0` as empty, so the SM-09 profile's explicit zero-day grace became
the production default of 14 days. An expired disposable activation therefore
remained in grace instead of reporting `expired`.

## Resolution

Use key presence to distinguish an omitted setting from an explicit zero. The
chart now forwards `0` unchanged and retains 14 days only when the value is
absent.
