#!/bin/sh
# The same checks run locally and in GitHub Actions. Requires Xcode, uv and shellcheck.
set -eu
cd "$(dirname "$0")/.."

scripts/fetch-deps.sh
uv run --no-project --with-requirements requirements-dev.txt ruff format --check scripts
xcrun swift-format lint --strict --recursive Sources Tests Package.swift scripts/render-menu.swift
uv run --no-project --with-requirements requirements-dev.txt ruff check scripts
shellcheck scripts/*.sh
plutil -lint Resources/Info.plist
swift build
swift test
