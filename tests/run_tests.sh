#!/usr/bin/env bash
# Test runner for durable.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Running durable.sh test suite..."
echo

# Run the main test suite
bash "$SCRIPT_DIR/test_durable.sh"

echo
echo "✅ All tests passed!"