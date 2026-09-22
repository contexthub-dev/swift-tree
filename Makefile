# The only place these commands are written. The workflows call these targets,
# so a contributor's local run is byte-identical to the CI gate.
SWIFT_FORMAT_PATHS := Package.swift Sources Tests demo/Package.swift demo/Sources

.PHONY: format-check format build test demo

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

## Build the demo app (run it with `swift run --package-path demo`).
demo:
	swift build --package-path demo
