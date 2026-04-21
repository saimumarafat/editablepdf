#!/bin/sh
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# Builds the EditablePDF target (requires Xcode). DerivedData uses the default location.
exec xcodebuild -scheme EditablePDF -destination 'generic/platform=iOS' build "$@"
