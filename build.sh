#!/usr/bin/env bash
## build.sh — headless CI/local build pipeline for Bottleneck.
## Runs the full headless test suite first (aborts the build on red tests), then exports each
## requested platform preset via `godot --headless --export-release`, zipping each output.
## Gracefully skips the export step (exit 0, clear message) when export templates are not
## installed -- the test gate above still ran either way. See docs/ARCHITECTURE.md §9/§10.
##
## Usage:
##   ./build.sh                  # tests, then export+zip every platform
##   ./build.sh linux web        # tests, then export+zip just these platforms
## Env:
##   GODOT_BIN   path to the Godot 4.5 binary (default: /home/user/godot/godot)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

GODOT_BIN="${GODOT_BIN:-/home/user/godot/godot}"
BUILDS_DIR="$ROOT_DIR/builds"
TEMPLATES_DIR="$HOME/.local/share/godot/export_templates"

# key -> "Preset Name|output subdir|exported file/bundle name|zip file name"
declare -A PRESETS=(
	[windows]="Windows Desktop|windows|bottleneck.exe|bottleneck-windows.zip"
	[linux]="Linux|linux|bottleneck.x86_64|bottleneck-linux.zip"
	[macos]="macOS|macos|Bottleneck.app|bottleneck-macos.zip"
	[web]="Web|web|index.html|bottleneck-web.zip"
)

log() { printf '[build.sh] %s\n' "$1"; }

require_zip() {
	if ! command -v zip >/dev/null 2>&1; then
		log "ERROR: 'zip' is required to package builds but is not on PATH."
		exit 1
	fi
}

run_tests() {
	log "Running headless test suite..."
	if ! "$GODOT_BIN" --headless --path "$ROOT_DIR" -s res://tests/run_tests.gd; then
		log "Tests FAILED -- aborting build."
		exit 1
	fi
	log "Tests passed."
}

templates_installed() {
	[[ -d "$TEMPLATES_DIR" ]] && [[ -n "$(find "$TEMPLATES_DIR" -mindepth 1 -maxdepth 2 -print -quit 2>/dev/null)" ]]
}

export_one() {
	local key="$1"
	local preset_name subdir fname zip_name
	IFS='|' read -r preset_name subdir fname zip_name <<< "${PRESETS[$key]}"
	local out_dir="$BUILDS_DIR/$subdir"
	local export_path="$out_dir/$fname"
	mkdir -p "$out_dir"

	log "Exporting '$preset_name' -> $export_path"
	if ! "$GODOT_BIN" --headless --path "$ROOT_DIR" --export-release "$preset_name" "$export_path"; then
		log "Export FAILED for '$preset_name' -- see Godot output above."
		return 1
	fi

	local zip_path="$BUILDS_DIR/$zip_name"
	log "Zipping $subdir/ -> $zip_path"
	rm -f "$zip_path"
	( cd "$out_dir" && zip -r -q "$zip_path" . )
	log "Done: $zip_path"
}

main() {
	run_tests

	if ! templates_installed; then
		log "No Godot export templates found under $TEMPLATES_DIR --"
		log "skipping platform exports (tests above already ran and gate the build)."
		log "Install export templates (Editor > Manage Export Templates, or download"
		log "Godot_v4.5-stable_export_templates.tpz and extract to"
		log "$TEMPLATES_DIR/4.5.stable/) and re-run to produce builds/."
		exit 0
	fi

	require_zip
	mkdir -p "$BUILDS_DIR"

	local targets=("$@")
	if [[ ${#targets[@]} -eq 0 ]]; then
		targets=(windows linux macos web)
	fi

	local failures=0
	for t in "${targets[@]}"; do
		if [[ -z "${PRESETS[$t]:-}" ]]; then
			log "Unknown target '$t' -- expected one of: ${!PRESETS[*]}"
			failures=$((failures + 1))
			continue
		fi
		if ! export_one "$t"; then
			failures=$((failures + 1))
		fi
	done

	if [[ $failures -gt 0 ]]; then
		log "$failures export(s) failed."
		exit 1
	fi
	log "All exports complete: $BUILDS_DIR"
}

main "$@"
