# The only place these commands are written. The workflows call these targets,
# so a contributor's local run is byte-identical to the CI gate.
SWIFT_FORMAT_PATHS := Package.swift Sources Tests demo/Package.swift demo/Sources demo/Tests

.PHONY: format-check format build test demo demo-test

## Report violations as file:line:col: error: [Rule]. Non-zero exit if any.
format-check:
	swift format lint --strict --recursive $(SWIFT_FORMAT_PATHS)

## Rewrite the same paths in place to match swift format's defaults.
format:
	swift format --in-place --recursive $(SWIFT_FORMAT_PATHS)

build:
	swift build

test:
	swift test

## Build and launch the demo app. `make demo ROOT=~/code/repo` opens that folder directly.
demo:
	swift run --package-path demo SwiftTreeDemo $(if $(ROOT),-root $(ROOT))

## Build and test the demo without launching it (the CI gate).
demo-test:
	swift build --package-path demo
	swift test --package-path demo
