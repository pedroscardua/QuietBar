#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p build/audio
clang -std=c11 -O2 -Wall -Wextra -Werror scripts/generate_audio.c -o build/generate-audio
build/generate-audio build/audio
