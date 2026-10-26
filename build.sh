#!/bin/zsh
set -eu
cd "${0:A:h}"
export MACOSX_DEPLOYMENT_TARGET=13.0
quietbar_output="${QUIETBAR_OUTPUT_DIR:-$PWD/build/QuietBar.app}"
./scripts/generate-audio.sh
mkdir -p "$quietbar_output/Contents/MacOS" "$quietbar_output/Contents/Resources/Audio"
clang -std=c11 -O3 -Wall -Wextra -Werror -c Sources/AudioCore.c -o build/AudioCore.o
swiftc -swift-version 5 -O -import-objc-header Sources/AudioCore.h Sources/QuietBar.swift build/AudioCore.o -framework AppKit -framework AVFoundation -o build/QuietBar-next
cp build/QuietBar-next "$quietbar_output/Contents/MacOS/QuietBar"
cp build/audio/*.f32 "$quietbar_output/Contents/Resources/Audio/"
cp Info.plist "$quietbar_output/Contents/Info.plist"
cp LICENSE "$quietbar_output/Contents/Resources/LICENSE.txt"
codesign --force --sign - "$quietbar_output"
codesign --verify --strict "$quietbar_output"
echo "App: $quietbar_output"
