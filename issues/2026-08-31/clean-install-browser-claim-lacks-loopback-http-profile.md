# Clean-install browser claim lacks loopback HTTP profile

## Problem

The disposable browser gate reaches the UI through a loopback HTTP
port-forward. Its local values profile did not opt into the paired transport
and cookie settings required for a one-time setup claim, so the server rejected
the claim before issuing the bounded setup session.

## Resolution

Set the explicit local-development public URL, loopback HTTP allowance and
non-secure setup cookie only in the disposable E2E profile. Production chart
defaults remain HTTPS-only with secure cookies.
