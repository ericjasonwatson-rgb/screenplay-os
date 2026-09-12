#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 1 || ! -f "$1" ]]; then
    echo "Usage: Scripts/benchmark-typing.sh /absolute/path/to/script.json" >&2
    exit 1
fi
fixture_directory="$(cd "$(dirname "$1")" && pwd)"
fixture_path="$fixture_directory/$(basename "$1")"
# The test always edits a temporary copy with isolated preferences and saves.
for configuration in debug release; do
    echo "Typing benchmark: $configuration"
    SCREENPLAYOS_BUILD_CONFIGURATION="$configuration" \
    SCREENPLAYOS_BENCHMARK_FIXTURE="$fixture_path" \
        ./Scripts/test.sh --filter longScriptTypingBenchmarkWhenRequested
done
