# SM-09 resource scan must not wait for Runner readiness

The resource-scan gate unnecessarily waited for Runner `online`. Agent scans
are independent of Runner command polling, so that wait exhausted the harness
timeout before it could request the scan.
