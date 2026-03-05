#!/usr/bin/env bash
#
# Generate a synthetic Clojure project for benchmarking gen_build.
#
# Usage: ./tools/gen_test_project.sh [OPTIONS]
#   --dir DIR         Output directory (default: /tmp/bench-project)
#   --namespaces N    Number of namespaces to generate (default: 50)
#   --depth D         Max directory nesting depth (default: 3)
#   --deps N          Average number of internal deps per namespace (default: 2)
#   --imports N       Average number of Java imports per namespace (default: 1)
#
# The generated project has:
# - A deps.edn with org.clojure/clojure dependency
# - N namespaces spread across directories up to depth D
# - Each namespace :requires ~deps other generated namespaces
# - Some namespaces are test files (*_test.clj)

set -euo pipefail

DIR="/tmp/bench-project"
NUM_NS=50
MAX_DEPTH=3
AVG_DEPS=2
AVG_IMPORTS=1

while [[ $# -gt 0 ]]; do
  case $1 in
    --dir) DIR="$2"; shift 2;;
    --namespaces) NUM_NS="$2"; shift 2;;
    --depth) MAX_DEPTH="$2"; shift 2;;
    --deps) AVG_DEPS="$2"; shift 2;;
    --imports) AVG_IMPORTS="$2"; shift 2;;
    *) echo "Unknown option: $1"; exit 1;;
  esac
done

echo "Generating test project:"
echo "  dir=$DIR"
echo "  namespaces=$NUM_NS"
echo "  depth=$MAX_DEPTH"
echo "  avg-deps=$AVG_DEPS"

rm -rf "$DIR"
mkdir -p "$DIR/src"

# Generate namespace paths
declare -a NS_NAMES=()
declare -a NS_PATHS=()

# Generate random namespace names with directory structure
SEGMENTS=("alpha" "beta" "gamma" "delta" "epsilon" "zeta" "eta" "theta"
          "iota" "kappa" "lambda" "mu" "nu" "xi" "omicron" "pi"
          "rho" "sigma" "tau" "upsilon" "phi" "chi" "psi" "omega"
          "core" "util" "impl" "api" "model" "service" "handler" "db"
          "config" "middleware" "routes" "schema" "transform" "process")

for i in $(seq 1 "$NUM_NS"); do
  # Determine depth for this namespace (1 to MAX_DEPTH)
  depth=$(( (RANDOM % MAX_DEPTH) + 1 ))

  # Build namespace segments
  ns_parts=""
  path_parts=""
  for d in $(seq 1 "$depth"); do
    seg_idx=$(( (RANDOM + i * 7 + d * 13) % ${#SEGMENTS[@]} ))
    seg="${SEGMENTS[$seg_idx]}"
    if [ $d -eq 1 ]; then
      ns_parts="bench.${seg}"
      path_parts="${seg}"
    elif [ $d -lt "$depth" ]; then
      ns_parts="${ns_parts}.${seg}"
      path_parts="${path_parts}/${seg}"
    fi
  done

  # Last segment is the file name - make some of them tests
  if (( RANDOM % 5 == 0 )); then
    file_seg="ns${i}_test"
  else
    file_seg="ns${i}"
  fi
  ns_parts="${ns_parts}.${file_seg}"
  path_parts="${path_parts}/${file_seg}"

  NS_NAMES+=("$ns_parts")
  NS_PATHS+=("$path_parts")
done

# Generate .clj files
for i in $(seq 0 $(( NUM_NS - 1 ))); do
  ns_name="${NS_NAMES[$i]}"
  ns_path="${NS_PATHS[$i]}"
  file_path="$DIR/src/${ns_path//-/_}.clj"

  mkdir -p "$(dirname "$file_path")"

  # Pick random deps from earlier namespaces (to avoid cycles)
  requires=""
  if [ "$i" -gt 0 ] && [ "$AVG_DEPS" -gt 0 ]; then
    num_deps=$(( RANDOM % (AVG_DEPS * 2 + 1) ))
    if [ "$num_deps" -gt "$i" ]; then
      num_deps=$i
    fi
    for _ in $(seq 1 "$num_deps"); do
      dep_idx=$(( RANDOM % i ))
      dep_name="${NS_NAMES[$dep_idx]}"
      if [ -z "$requires" ]; then
        requires="            [${dep_name}]"
      else
        requires="${requires}
            [${dep_name}]"
      fi
    done
  fi

  # Build the ns form
  if [ -n "$requires" ]; then
    cat > "$file_path" <<CLJEOF
(ns ${ns_name}
  (:require ${requires}))

(defn process-${i} [x]
  (inc x))
CLJEOF
  else
    cat > "$file_path" <<CLJEOF
(ns ${ns_name})

(defn process-${i} [x]
  (inc x))
CLJEOF
  fi
done

# Generate deps.edn
cat > "$DIR/deps.edn" <<'DEPSEOF'
{:deps
 {org.clojure/clojure {:mvn/version "1.12.1"}}
 :paths ["src"]
 :mvn/repos {"maven" {:url "https://repo1.maven.org/maven2"}
             "clojars" {:url "https://repo.clojars.org/"}}}
DEPSEOF

# Summary
num_test=$(printf '%s\n' "${NS_NAMES[@]}" | grep -c '_test' || true)
num_dirs=$(find "$DIR/src" -type d | wc -l)
echo ""
echo "Generated project at $DIR:"
echo "  Total namespaces: $NUM_NS"
echo "  Test namespaces:  $num_test"
echo "  Directories:      $num_dirs"
echo "  Source root:      $DIR/src"
echo ""
echo "To benchmark:"
echo "  bazel run //src/rules_clojure:benchmark -- \\"
echo "    :deps-edn-path $DIR/deps.edn \\"
echo "    :repository-dir \$HOME/.m2/repository \\"
echo "    :command srcs"
