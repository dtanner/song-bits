project    := "SongBits.xcodeproj"
scheme     := "SongBits"
bundle_id  := "com.dantanner.songbits"
sim        := "iPhone 17"
phone      := env_var_or_default("PHONE", "")

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

# Build, install, and launch on your iPhone over USB or Wi-Fi (auto-discovers it; or `PHONE=<name-or-udid> just device`)
device: generate
    #!/usr/bin/env bash
    set -euo pipefail
    dev="{{phone}}"
    if [ -z "$dev" ]; then
        json=$(mktemp)
        xcrun devicectl list devices --json-output "$json" >/dev/null
        # First paired iPhone whose tunnel isn't unavailable — devicectl brings
        # the tunnel up on demand, so "disconnected" still deploys over Wi-Fi.
        dev=$(python3 -c "import json; ds=json.load(open('$json'))['result']['devices']; ok=lambda d: d.get('hardwareProperties',{}).get('productType','').startswith('iPhone') and d.get('connectionProperties',{}).get('pairingState')=='paired' and d.get('connectionProperties',{}).get('tunnelState')!='unavailable'; print(next((d['hardwareProperties']['udid'] for d in ds if ok(d)), ''))")
        rm -f "$json"
    fi
    if [ -z "$dev" ]; then
        echo "No paired iPhone reachable. Is the phone awake and on the same Wi-Fi? Run 'just devices' to inspect, or PHONE=<name-or-udid> just device"
        exit 1
    fi
    xcodebuild -project {{project}} -scheme {{scheme}} \
        -destination "generic/platform=iOS" \
        -derivedDataPath build/dd-device \
        -allowProvisioningUpdates \
        build
    xcrun devicectl device install app --device "$dev" \
        "build/dd-device/Build/Products/Debug-iphoneos/{{scheme}}.app"
    xcrun devicectl device process launch --device "$dev" {{bundle_id}}

# Screenshot the booted simulator into marketing/screenshots/<name>.png
shot name:
    @mkdir -p marketing/screenshots
    xcrun simctl io booted screenshot marketing/screenshots/{{name}}.png

# Open the project in Xcode
open: generate
    open {{project}}

# Remove build artifacts
clean:
    rm -rf build
