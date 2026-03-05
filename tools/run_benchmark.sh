#!/usr/bin/env bash
#
# Run gen_build benchmarks.
#
# Usage:
#   ./tools/run_benchmark.sh [--project DIR] [--command srcs|deps] [--iterations N] [--warmup N]
#
# Defaults to benchmarking the examples/simple project with 3 iterations.
#
# Examples:
#   # Benchmark examples/simple
#   ./tools/run_benchmark.sh
#
#   # Benchmark a synthetic project
#   ./tools/gen_test_project.sh --namespaces 100 --dir /tmp/bench-100
#   ./tools/run_benchmark.sh --project /tmp/bench-100
#
#   # Benchmark deps command
#   ./tools/run_benchmark.sh --project examples/stress --command deps

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

PROJECT="examples/simple"
COMMAND="srcs"
ITERATIONS="3"
WARMUP="1"

while [[ $# -gt 0 ]]; do
  case $1 in
    --project) PROJECT="$2"; shift 2;;
    --command) COMMAND="$2"; shift 2;;
    --iterations) ITERATIONS="$2"; shift 2;;
    --warmup) WARMUP="$2"; shift 2;;
    *) echo "Unknown option: $1"; exit 1;;
  esac
done

# Resolve project path
if [[ "$PROJECT" = /* ]]; then
  PROJECT_DIR="$PROJECT"
else
  PROJECT_DIR="$REPO_DIR/$PROJECT"
fi

DEPS_EDN="$PROJECT_DIR/deps.edn"
if [ ! -f "$DEPS_EDN" ]; then
  echo "Error: deps.edn not found at $DEPS_EDN"
  exit 1
fi

# Use system M2 repo or fall back to default
M2_REPO="${M2_REPO:-$HOME/.m2/repository}"

echo "Benchmarking: $PROJECT_DIR"
echo "  command:    $COMMAND"
echo "  iterations: $ITERATIONS"
echo "  warmup:     $WARMUP"
echo "  M2 repo:    $M2_REPO"
echo ""

cd "$REPO_DIR"

# Build the benchmark binary
echo "Building benchmark binary..."
bazel build //src/rules_clojure:benchmark 2>&1 | tail -3
echo ""

# Run the benchmark
bazel run //src/rules_clojure:benchmark -- \
  ":deps-edn-path" "$DEPS_EDN" \
  ":repository-dir" "$M2_REPO" \
  ":command" "$COMMAND" \
  ":iterations" "$ITERATIONS" \
  ":warmup" "$WARMUP" \
  ":aliases" "[]"
