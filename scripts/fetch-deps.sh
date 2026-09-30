#!/bin/sh
# Downloads the denoiser runtime and model into build/deps (not committed):
#   sherpa-onnx v1.13.8 C API + ONNX Runtime (Apache-2.0 / MIT), DPDFNet2 48 kHz model (Apache-2.0, Ceva).
set -eu
cd "$(dirname "$0")/.."
DEPS=build/deps
mkdir -p "$DEPS"
if [ ! -f "$DEPS/sherpa/lib/libsherpa-onnx-c-api.dylib" ]; then
    curl -sSL -o "$DEPS/sherpa.tar.bz2" \
        https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/sherpa-onnx-v1.13.8-osx-arm64-shared.tar.bz2
    tar xjf "$DEPS/sherpa.tar.bz2" -C "$DEPS"
    rm -rf "$DEPS/sherpa" && mv "$DEPS/sherpa-onnx-v1.13.8-osx-arm64-shared" "$DEPS/sherpa"
    rm "$DEPS/sherpa.tar.bz2"
fi
if [ ! -f "$DEPS/dpdfnet2_48khz_hr.onnx" ]; then
    curl -sSL -o "$DEPS/dpdfnet2_48khz_hr.onnx" \
        https://github.com/k2-fsa/sherpa-onnx/releases/download/speech-enhancement-models/dpdfnet2_48khz_hr.onnx
fi
echo "deps ready in $DEPS"
