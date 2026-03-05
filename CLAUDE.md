# CLAUDE.md - Development Guide for rules_clojure

## Project Overview

Bazel build rules for Clojure/ClojureScript projects, produced by Griffin Bank. Provides `clojure_library`, `clojure_binary`, `clojure_test`, and `clojure_repl` rules with AOT compilation support, tools.deps integration, and persistent worker-based compilation.

## Prerequisites

- **Java 21+** (OpenJDK)
- **Bazelisk** (manages Bazel version automatically via `.bazeliskrc` -> Bazel 7.4.1)
- **Clojure CLI** (for REPL and tools.deps)

## Quick Setup

```sh
# Install Bazelisk (if not present)
curl -fsSL https://github.com/bazelbuild/bazelisk/releases/download/v1.25.0/bazelisk-linux-amd64 -o /usr/local/bin/bazel && chmod +x /usr/local/bin/bazel

# Install Clojure CLI (if not present)
curl -fsSL https://download.clojure.org/install/linux-install-1.12.0.1530.sh | bash
```

## Build Commands

```sh
# Build all source targets (main library + rules)
bazel build //src/... //rules/...

# Build specific targets
bazel build //src/rules_clojure:worker        # The persistent compilation worker
bazel build //src/rules_clojure:bootstrap     # Bootstrap resources (source JARs)
bazel build //src/rules_clojure:libcompile    # Compiled compiler library
bazel build //src/rules_clojure:libfs         # Compiled filesystem utilities
bazel build //src/rules_clojure:libworker     # Compiled worker library
bazel build //src/rules_clojure:gen_build     # BUILD file generator binary

# Build everything
bazel build //...
```

## Test Commands

```sh
# Run all tests
bazel test //...

# Run specific tests
bazel test //test/rules_clojure:worker-test
bazel test //test/rules_clojure:compile-test
bazel test //test/rules_clojure:persistent-classloader-test

# Example project tests (run from their directories)
cd examples/simple && bazel test //...
cd examples/stress && bazel test //...
```

## Project Structure

```
src/rules_clojure/       # Core Clojure source
  compile.clj            # AOT compilation logic
  worker.clj             # Persistent Bazel worker
  fs.clj                 # Filesystem utilities
  gen_build.clj          # BUILD file generator
  testrunner.clj         # Test execution framework
  persistent_classloader.clj  # Classloader isolation
  bootstrap_*.clj        # Bootstrap compilation scripts
  namespace/             # Namespace parsing utilities
  tools/reader/          # Vendored tools.reader library

test/rules_clojure/      # Tests (clojure.test)
  compile_test.clj
  worker_test.clj
  persistent_classloader_test.clj

rules/                   # Bazel rule implementations (.bzl files)
  jar.bzl                # clojure_library/clojure_jar rule impl
  repl.bzl               # clojure_repl rule impl
  cljs.bzl               # ClojureScript rules
  common.bzl             # Shared utilities
  namespace.bzl          # Namespace handling
  tools_deps.bzl         # tools.deps integration

examples/
  simple/                # Basic usage example
  stress/                # Complex dependency test

rules.bzl                # Public rule definitions (clojure_library, clojure_binary, clojure_test, clojure_repl)
repositories.bzl         # Repository setup (rules_clojure_deps)
setup.bzl                # Initialization (rules_clojure_setup)
WORKSPACE                # Dependencies (rules_jvm_external, maven_install)
```

## Architecture

- **Persistent Worker**: Compilation uses a Bazel persistent worker (`src/rules_clojure/worker.clj`) that stays running between builds for faster incremental compilation
- **Non-transitive AOT**: Each namespace is compiled independently using isolated classloaders to prevent protocol/deftype conflicts
- **Bootstrap Pattern**: The worker/compiler is bootstrapped from source using `java_library` + `genrule` (see `src/rules_clojure/BUILD` bootstrap targets)
- **tools.deps Integration**: `clojure_tools_deps()` macro in `rules/tools_deps.bzl` resolves deps.edn dependencies for Bazel

## Key Files to Understand

- `rules.bzl` - Public API: `clojure_library`, `clojure_binary`, `clojure_test`, `clojure_repl`
- `rules/jar.bzl` - Core compilation rule implementation
- `src/rules_clojure/compile.clj` - Compilation orchestration
- `src/rules_clojure/worker.clj` - Persistent worker protocol
- `WORKSPACE` - Dependency declarations
- `design.md` - Architecture rationale and design decisions

## Bazel Configuration

- `.bazeliskrc` - Specifies Bazel 7.4.1
- `.bazelrc` - Build flags (Java runtime, test output settings)
- `.bazelignore` - Excludes `examples/` from root workspace analysis
- This project uses WORKSPACE (not bzlmod/MODULE.bazel)
- Add `build --noenable_bzlmod` to `.bazelrc` if Bazel tries to use bzlmod

## Dependency Management

- **Maven deps** (for this project): Defined in WORKSPACE via `maven_install`, pinned in `frozen_deps_install.json`
- **Internal deps** (for the rules themselves): Pre-built in `deps/rules_clojure_maven_deps.zip`
- **Repin deps**: `bazel run @frozen_deps//:pin` and `python3 tools/freeze-deps.py` for internal deps
- Repositories: Maven Central + Clojars

## Clojure Conventions

- Namespace `rules-clojure.*` maps to files under `src/rules_clojure/`
- Test namespaces: `rules-clojure.*-test` in `test/rules_clojure/`
- Clojure files use `-` in namespace names but `_` in filenames (standard Clojure convention)
- The project vendors `tools.reader` and `java.classpath` to avoid dependency conflicts
