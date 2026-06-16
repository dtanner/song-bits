project    := "SongBits.xcodeproj"
scheme     := "SongBits"
bundle_id  := "com.dantanner.songbits"
sim        := "iPhone 17"
device     := env_var_or_default("DEVICE", "")

# List available recipes
default:
    @just --list

# Regenerate the Xcode project from project.yml
generate:
    xcodegen generate

# Build for the simulator
build: generate
    xcodebuild -project {{project}} -scheme {{scheme}} \
        -destination "generic/platform=iOS Simulator" \
        -derivedDataPath build/dd \
        build

# Build, install, and launch in the simulator
run: build
    #!/usr/bin/env bash
    set -euo pipefail
    open -a Simulator
    xcrun simctl boot "{{sim}}" 2>/dev/null || true
    app="build/dd/Build/Products/Debug-iphonesimulator/{{scheme}}.app"
    xcrun simctl install booted "$app"
    xcrun simctl launch booted {{bundle_id}}

# Stream the app's logs from the booted simulator
logs:
    xcrun simctl spawn booted log stream --level debug \
        --predicate 'subsystem CONTAINS "{{bundle_id}}"'

# Run the test suite on the simulator
test: generate
    xcodebuild -project {{project}} -scheme {{scheme}} \
        -destination "platform=iOS Simulator,name={{sim}}" \
        test

# List connected physical devices and their UDIDs
devices:
    xcrun devicectl list devices

# Build, install, and launch on a connected iPhone
#   uses the first connected device, or `DEVICE=<udid> just deploy`
# requires a signing team (set DEVELOPMENT_TEAM in project.yml once your account is ready)
deploy: generate
    #!/usr/bin/env bash
    set -euo pipefail
    xcodebuild -project {{project}} -scheme {{scheme}} \
        -destination "generic/platform=iOS" \
        -derivedDataPath build/dd-device \
        -allowProvisioningUpdates \
        build
    app="build/dd-device/Build/Products/Debug-iphoneos/{{scheme}}.app"
    dev="{{device}}"
    if [ -z "$dev" ]; then
        xcrun devicectl list devices --json-output /tmp/sb-devices.json >/dev/null
        dev=$(python3 -c "import json; d=json.load(open('/tmp/sb-devices.json')); print(next((x['hardwareProperties']['udid'] for x in d['result']['devices'] if x['connectionProperties'].get('tunnelState') != 'unavailable'), ''))")
    fi
    if [ -z "$dev" ]; then
        echo "No connected device found. Run 'just devices' and retry with DEVICE=<udid> just deploy"
        exit 1
    fi
    xcrun devicectl device install app --device "$dev" "$app"
    xcrun devicectl device process launch --device "$dev" {{bundle_id}}

# Open the project in Xcode
open: generate
    open {{project}}

# Remove build artifacts
clean:
    rm -rf build
