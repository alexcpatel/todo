#!/bin/bash
set -e

cd "$(dirname "$0")"

ACTION="${1:-build}"
SCHEME="Todo"
PROJECT="Todo.xcodeproj"
BUILD_DIR="build"
APP_NAME="Todo.app"

case "$ACTION" in
  build)
    echo "Building for macOS..."
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
      -destination "platform=macOS" \
      -configuration Debug \
      -derivedDataPath "$BUILD_DIR" \
      -allowProvisioningUpdates \
      -allowProvisioningDeviceRegistration \
      build
    echo "Build complete: $BUILD_DIR/Build/Products/Debug/$APP_NAME"
    ;;
    
  run)
    echo "Building and running..."
    $0 build
    open "$BUILD_DIR/Build/Products/Debug/$APP_NAME"
    ;;
    
  clean)
    echo "Cleaning..."
    rm -rf "$BUILD_DIR"
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" clean 2>/dev/null || true
    echo "Clean complete"
    ;;
    
  xcode)
    open -a Xcode "$PROJECT"
    ;;
    
  *)
    echo "Usage: ./build.sh [build|run|clean|xcode]"
    echo "  build - Build signed debug (default)"
    echo "  run   - Build and launch app"
    echo "  clean - Remove build artifacts"
    echo "  xcode - Open project in Xcode"
    ;;
esac
