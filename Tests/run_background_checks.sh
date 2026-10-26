#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export MACOSX_DEPLOYMENT_TARGET=13.0
mkdir -p build/Checks.app/Contents/{MacOS,Resources} build/reports
./scripts/generate-audio.sh
clang -std=c11 -O3 -Wall -Wextra -Werror -c Sources/AudioCore.c -o build/check-AudioCore.o
clang -std=c11 -O3 -dynamiclib Sources/AudioCore.c -o build/libAudioCore.dylib
python3 Tests/check_assets.py
python3 - <<'PY'
from pathlib import Path
s=Path('Sources/QuietBar.swift').read_text().split('\nlet app = NSApplication.shared\n')[0]
s='\n'.join('let supportFolder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)' if line.startswith('let supportFolder = ') else line for line in s.splitlines())
for name in ['app_logic','quick_panel','missing_audio']:
    Path('build/check-'+name+'.swift').write_text(s+'\n'+Path('Tests/check_'+name+'.swift').read_text())
PY
ln -sfn "$PWD/build/audio" build/Checks.app/Contents/Resources/Audio
for kind in app_logic quick_panel missing_audio; do
  swiftc -swift-version 5 -Onone -import-objc-header Sources/AudioCore.h "build/check-$kind.swift" build/check-AudioCore.o -framework AppKit -framework AVFoundation -o build/Checks.app/Contents/MacOS/Checks
  if [[ "$kind" == app_logic ]]; then
    build/Checks.app/Contents/MacOS/Checks "$PWD/build/test-state" "$PWD/build/reports/app-logic-test.json"
  elif [[ "$kind" == quick_panel ]]; then
    build/Checks.app/Contents/MacOS/Checks "$PWD/build/test-state" "$PWD/build/reports"
  else
    # Isolated bundle, missing resources, must throw instead of double-free/crash.
    mkdir -p build/Missing.app/Contents/MacOS
    cp build/Checks.app/Contents/MacOS/Checks build/Missing.app/Contents/MacOS/Checks
    build/Missing.app/Contents/MacOS/Checks "$PWD/build/test-state"
  fi
done
python3 Tests/check_audio.py
python3 Tests/check_background.py
