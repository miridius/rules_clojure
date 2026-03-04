#!/usr/bin/env bash
set -euo pipefail

# Session start hook for rules_clojure development
# Installs Bazelisk, Clojure CLI, and configures proxy/SSL for Bazel

SETUP_MARKER="/tmp/.rules_clojure_setup_done"

# Skip if already set up in this container
if [ -f "$SETUP_MARKER" ]; then
    echo "Development environment already configured."
    exit 0
fi

echo "Setting up rules_clojure development environment..."

# Install Bazelisk (provides 'bazel' command, auto-downloads correct Bazel version)
if ! command -v bazel &> /dev/null; then
    echo "Installing Bazelisk..."
    curl -fsSL https://github.com/bazelbuild/bazelisk/releases/download/v1.25.0/bazelisk-linux-amd64 -o /usr/local/bin/bazel
    chmod +x /usr/local/bin/bazel
    echo "Bazelisk installed: $(bazel --version 2>&1 | tail -1)"
fi

# Install Clojure CLI tools
if ! command -v clojure &> /dev/null; then
    echo "Installing Clojure CLI..."
    curl -fsSL https://download.clojure.org/install/linux-install-1.12.0.1530.sh -o /tmp/clojure-install.sh
    chmod +x /tmp/clojure-install.sh
    /tmp/clojure-install.sh
    rm -f /tmp/clojure-install.sh
    echo "Clojure installed: $(clojure --version 2>&1)"
fi

# Configure Bazel proxy settings if running behind a proxy
if [ -n "${JAVA_TOOL_OPTIONS:-}" ] && echo "$JAVA_TOOL_OPTIONS" | grep -q "proxyHost"; then
    PROXY_HOST=$(echo "$JAVA_TOOL_OPTIONS" | grep -oP '(?<=-Dhttp.proxyHost=)\S+')
    PROXY_PORT=$(echo "$JAVA_TOOL_OPTIONS" | grep -oP '(?<=-Dhttp.proxyPort=)\S+')
    PROXY_USER=$(echo "$JAVA_TOOL_OPTIONS" | grep -oP '(?<=-Dhttp.proxyUser=)\S+')
    PROXY_PASSWORD=$(echo "$JAVA_TOOL_OPTIONS" | grep -oP '(?<=-Dhttp.proxyPassword=)\S+' | head -1)

    if [ -n "$PROXY_HOST" ] && [ -n "$PROXY_PORT" ]; then
        echo "Configuring Bazel proxy settings..."

        # Import proxy CA certificates into system Java truststore
        JAVA_HOME_DIR=$(dirname "$(dirname "$(readlink -f "$(which java)")")")
        CUSTOM_TRUSTSTORE="$HOME/.bazel_truststore"
        if [ -f "$JAVA_HOME_DIR/lib/security/cacerts" ]; then
            cp "$JAVA_HOME_DIR/lib/security/cacerts" "$CUSTOM_TRUSTSTORE"
            for cert in /usr/local/share/ca-certificates/*.crt; do
                if [ -f "$cert" ]; then
                    name=$(basename "$cert" .crt)
                    "$JAVA_HOME_DIR/bin/keytool" -importcert -noprompt -trustcacerts \
                        -alias "$name" -file "$cert" \
                        -keystore "$JAVA_HOME_DIR/lib/security/cacerts" \
                        -storepass changeit 2>/dev/null || true
                fi
            done
        fi

        # Write Bazel proxy config to home .bazelrc
        cat > "$HOME/.bazelrc" << EOF
startup --host_jvm_args=-Dhttp.proxyHost=${PROXY_HOST}
startup --host_jvm_args=-Dhttp.proxyPort=${PROXY_PORT}
startup --host_jvm_args=-Dhttps.proxyHost=${PROXY_HOST}
startup --host_jvm_args=-Dhttps.proxyPort=${PROXY_PORT}
startup --host_jvm_args=-Dhttp.proxyUser=${PROXY_USER}
startup --host_jvm_args=-Dhttp.proxyPassword=${PROXY_PASSWORD}
startup --host_jvm_args=-Dhttps.proxyUser=${PROXY_USER}
startup --host_jvm_args=-Dhttps.proxyPassword=${PROXY_PASSWORD}
startup --host_jvm_args=-Djdk.http.auth.tunneling.disabledSchemes=
startup --host_jvm_args=-Djdk.http.auth.proxying.disabledSchemes=
startup --host_jvm_args=-Djavax.net.ssl.trustStore=${CUSTOM_TRUSTSTORE}
EOF
        echo "Bazel proxy configuration written to $HOME/.bazelrc"
    fi
fi

# Ensure --noenable_bzlmod is in .bazelrc (this project uses WORKSPACE, not bzlmod)
if ! grep -q "noenable_bzlmod" .bazelrc 2>/dev/null; then
    echo "build --noenable_bzlmod" >> .bazelrc
fi

# Warm the Bazel cache with a build of core targets
echo "Warming Bazel cache..."
if bazel build //src/... //rules/... 2>&1 | tail -3; then
    echo "Core targets built successfully."
else
    echo "Warning: Core build had issues. Check 'bazel build //src/...' output."
fi

touch "$SETUP_MARKER"
echo "Development environment setup complete."
