# Runtime source and build provenance

LucidMic uses the official sherpa-onnx **v1.13.8 macOS arm64 shared no-TTS**
distribution, including ONNX Runtime **v1.28.2**. Its source bundle contains
unmodified source archives pinned by `scripts/runtime-sources.json`, with SHA-256
checksums. The full license notices are bundled in the app.

## sherpa-onnx

The sherpa source archive includes `.github/workflows/macos.yaml`, the top-level
`CMakeLists.txt`, and the dependency recipes in `cmake/`. The upstream release
build uses Release mode, shared libraries, `SHERPA_ONNX_ENABLE_TTS=OFF`, and universal
`arm64;x86_64` architectures. It configures, builds and installs with CMake, then
uses `lipo` to extract arm64 libraries and applies ad-hoc signatures. LucidMic
ships the arm64 no-TTS artifact. Its engine calls only the noise-removal API.
The archive and both shipped libraries are pinned and SHA-256 checked by
`scripts/fetch-deps.sh`, including cached libraries. The ONNX Runtime library and
DPDFNet2 model are unchanged from the full upstream distribution.

This supported upstream variant removes speech-synthesis code and the eSpeak NG
and piper-phonemize dependencies. Recognition and speaker-diarization components
remain: upstream does not offer a native denoising-only build switch. LucidMic
does not maintain a source fork to remove them.

Extract the archives inside `RuntimeSource/archives/` to inspect each dependency.
Their exact revisions and checksums are in `RuntimeSource/sources.json`; use those
revisions with the upstream CMake recipes or FetchContent source overrides.

## ONNX Runtime

The upstream [macOS build recipe](https://github.com/csukuangfj/onnxruntime-libs/blob/5cc3d2e84d9eade2562cf29a93fa3a520a75ca57/.github/workflows/macos-shared.yaml)
checks out microsoft/onnxruntime v1.28.2 with submodules. It removes the library
`SOVERSION` and `VERSION ${...}` properties from `cmake/onnxruntime.cmake`, producing
an unversioned library filename. It builds the arm64 and x86_64 slices separately
and joins them with `lipo`; the arm64 slice is distributed by LucidMic.

After applying that library-version patch, an equivalent arm64 build command is:

```sh
python3 tools/ci_build/build.py \
  --build_dir build-macos/arm64 --config Release \
  --cmake_generator Ninja --update --build --use_xcode --build_shared_lib \
  --compile_no_warning_as_error \
  --cmake_extra_defines onnxruntime_BUILD_UNIT_TESTS=OFF \
  --cmake_extra_defines CMAKE_INSTALL_PREFIX=install \
  --cmake_extra_defines CMAKE_OSX_ARCHITECTURES=arm64 \
  --cmake_extra_defines CMAKE_POLICY_VERSION_MINIMUM=3.5 \
  --apple_sysroot macosx --target install --parallel --skip_tests \
  --apple_deploy_target 10.15 --no_kleidiai --use_coreml
```

Download the exact [ONNX Runtime v1.28.2 source archive](https://github.com/microsoft/onnxruntime/archive/refs/tags/v1.28.2.tar.gz)
separately. This large MIT-licensed source archive is hosted upstream, rather than
duplicated in LucidMic's runtime source download. It includes the original build scripts, `.gitmodules`, and
`cmake/deps.txt`, which identifies its external build dependencies and download
checksums. Building needs Xcode, CMake, Ninja, Python, and the dependencies named
by those recipes. This source bundle is not a complete offline build environment.

The external build-recipes repository is linked as provenance; it is not copied
into the bundle. The commands and patch description above document the relevant
build facts. LucidMic's dependency-fetching and packaging scripts are in the main
repository and its release's Source code archive.
