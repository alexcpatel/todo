#!/bin/bash
set -e

cd "$(dirname "$0")"

# Configure these for your setup
# Find your device ID with: xcrun xctrace list devices
IPHONE_ID="YOUR-DEVICE-ID-HERE"

SCHEME="Todo"
PROJECT="Todo.xcodeproj"
BUNDLE_ID="com.alexpatel.Todo"

kill_app() {
    pkill -x Todo 2>/dev/null || true
}

case "${1:-help}" in
  mac)
    echo "Building for macOS..."
    kill_app
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
      -destination "platform=macOS" \
      -configuration Debug \
      -derivedDataPath "build-mac" \
      -allowProvisioningUpdates \
      build 2>&1 | tail -20
    echo "Launching on Mac..."
    open "build-mac/Build/Products/Debug/Todo.app"
    ;;

  iphone)
    echo "Building for iPhone..."
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
      -destination "id=$IPHONE_ID" \
      -configuration Debug \
      -derivedDataPath "build-ios" \
      -allowProvisioningUpdates \
      -allowProvisioningDeviceRegistration \
      build 2>&1 | tail -20
    echo "Installing on iPhone..."
    xcrun devicectl device install app --device "$IPHONE_ID" \
      "build-ios/Build/Products/Debug-iphoneos/Todo.app"
    echo "Launching on iPhone..."
    xcrun devicectl device process launch --device "$IPHONE_ID" "$BUNDLE_ID"
    ;;

  both)
    $0 mac &
    $0 iphone &
    wait
    echo "Both builds complete."
    ;;

  clean)
    echo "Cleaning..."
    kill_app
    rm -rf build-mac build-ios
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" clean 2>/dev/null || true
    echo "Clean complete"
    ;;

  xcode)
    open -a Xcode "$PROJECT"
    ;;

  *)
    echo "Usage: ./build.sh [mac|iphone|both|clean|xcode]"
    echo "  mac    - Build, install and run on this Mac"
    echo "  iphone - Build, install and run on iPhone"
    echo "  both   - Build and run on both simultaneously"
    echo "  clean  - Remove build artifacts"
    echo "  xcode  - Open project in Xcode"
    ;;
esac
