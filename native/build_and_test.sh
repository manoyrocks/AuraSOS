#!/usr/bin/env bash
# Builds the DSP test harness (and optionally the shared library) and runs it.
set -euo pipefail
cd "$(dirname "$0")"
CXX="${CXX:-clang++}"
mkdir -p build
"$CXX" -std=c++17 -O2 -Wall -Wextra -o build/dsp_test test/dsp_test.cpp dsp_engine.cpp
./build/dsp_test
if [ "${1:-}" = "--lib" ]; then
  case "$(uname -s)" in
    Darwin) "$CXX" -std=c++17 -O2 -shared -fPIC -fvisibility=hidden -o build/libaurasync_dsp.dylib dsp_engine.cpp audio_output_keep.cpp audio_output_apple.mm -fobjc-arc -framework AudioToolbox -framework Foundation ;;
    *) "$CXX" -std=c++17 -O2 -shared -fPIC -fvisibility=hidden -o build/libaurasync_dsp.so dsp_engine.cpp audio_output_keep.cpp audio_output_stub.cpp ;;
  esac
  echo "shared library built in native/build"
fi
