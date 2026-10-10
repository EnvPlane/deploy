module github.com/envplane/runner/pvc-copy-live-driver

go 1.26.9

require (
	github.com/envplane/contracts v0.1.109
	github.com/envplane/runner v0.0.0
)

// Local integration adapter, not released-module verification.
replace github.com/envplane/contracts => ../../../contracts

replace github.com/envplane/runner => ../../../runner
