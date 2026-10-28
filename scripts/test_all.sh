#!/usr/bin/env bash
# Runs every test suite and static analysis in the project.
# Usage:  ./scripts/test_all.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== pet_core (shared package)"
(cd packages/pet_core && dart pub get >/dev/null && dart analyze && dart test)

echo "== backend"
(cd backend && dart pub get >/dev/null && dart analyze && dart test)

echo "== Flutter app"
flutter pub get >/dev/null
# Infos (style/deprecation hints) are shown but do not fail the run;
# warnings and errors do.
flutter analyze --no-fatal-infos
flutter test

echo "All checks passed."
