#!/usr/bin/env bash
# secure-project-init.sh
#
# Bootstraps Dependency Security Guardrails defaults for new projects.
# Sets up .npmrc, uv/pip config, Dependabot, and git hooks.
#
# Usage:
#   ./secure-project-init.sh [npm|python|both]
#
# Examples:
#   ./secure-project-init.sh npm       # Node.js project
#   ./secure-project-init.sh python    # Python project
#   ./secure-project-init.sh both      # Polyglot project
#   ./secure-project-init.sh           # Defaults to both

set -euo pipefail

MODE="${1:-both}"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; }

# ─────────────────────────────────────────────
# npm setup
# ─────────────────────────────────────────────
setup_npm() {
    log "Configuring npm supply chain defaults..."

    if [ -f ".npmrc" ]; then
        warn ".npmrc already exists. Checking for required settings..."
        NEEDS_UPDATE=false

        if ! grep -q "ignore-scripts=true" .npmrc; then
            echo "ignore-scripts=true" >> .npmrc
            log "Added ignore-scripts=true to existing .npmrc"
            NEEDS_UPDATE=true
        fi
        if ! grep -q "save-exact=true" .npmrc; then
            echo "save-exact=true" >> .npmrc
            log "Added save-exact=true to existing .npmrc"
            NEEDS_UPDATE=true
        fi
        if ! grep -q "package-lock=true" .npmrc; then
            echo "package-lock=true" >> .npmrc
            log "Added package-lock=true to existing .npmrc"
            NEEDS_UPDATE=true
        fi

        if [ "$NEEDS_UPDATE" = false ]; then
            log ".npmrc already has all required settings"
        fi
    else
        cat > .npmrc <<'EOF'
# Dependency Security Guardrails defaults
# See: https://github.com/your-org/cdg-supply-chain-security
ignore-scripts=true
save-exact=true
package-lock=true
audit-level=moderate
EOF
        log "Created .npmrc"
    fi

    # Add security scripts to package.json if it exists
    if [ -f "package.json" ] && command -v jq &> /dev/null; then
        HAS_SECURITY=$(jq -r '.scripts["security:check"] // empty' package.json)
        if [ -z "$HAS_SECURITY" ]; then
            tmp=$(mktemp)
            jq '.scripts += {
                "security:check": "npm audit signatures && npm audit",
                "security:allow-scripts": "npx --yes @pnpm/allow-scripts"
            }' package.json > "$tmp" && mv "$tmp" package.json
            log "Added security scripts to package.json"
        fi
    fi
}

# ─────────────────────────────────────────────
# Python setup
# ─────────────────────────────────────────────
setup_python() {
    log "Configuring Python supply chain defaults..."

    if command -v uv &> /dev/null; then
        log "uv detected ($(uv --version))"

        # Initialize uv project if no pyproject.toml
        if [ ! -f "pyproject.toml" ]; then
            warn "No pyproject.toml found. Run 'uv init' to create one."
        fi

        # Create venv if not present
        if [ ! -d ".venv" ]; then
            uv venv .venv
            log "Created .venv via uv"
        fi
    else
        warn "uv not installed. Strongly recommended for hash-verified installs."
        warn "Install: curl -LsSf https://astral.sh/uv/install.sh | sh"

        # Fallback: harden pip config
        PIP_CONF_DIR="${HOME}/.config/pip"
        mkdir -p "$PIP_CONF_DIR"

        if [ ! -f "${PIP_CONF_DIR}/pip.conf" ]; then
            cat > "${PIP_CONF_DIR}/pip.conf" <<'EOF'
[global]
require-hashes = true

[install]
require-virtualenv = true
EOF
            log "Created pip.conf (require-hashes, require-virtualenv)"
        else
            warn "pip.conf already exists at ${PIP_CONF_DIR}/pip.conf"
        fi

        # Create venv
        if [ ! -d ".venv" ]; then
            python3 -m venv .venv
            log "Created .venv via python3"
        fi
    fi
}

# ─────────────────────────────────────────────
# Dependabot config
# ─────────────────────────────────────────────
setup_dependabot() {
    mkdir -p .github

    if [ -f ".github/dependabot.yml" ]; then
        log "Dependabot config already exists"
        return
    fi

    local ECOSYSTEMS=""

    if [ "$MODE" = "npm" ] || [ "$MODE" = "both" ]; then
        ECOSYSTEMS="${ECOSYSTEMS}
  - package-ecosystem: \"npm\"
    directory: \"/\"
    schedule:
      interval: \"weekly\"
      day: \"monday\"
    open-pull-requests-limit: 10
    versioning-strategy: \"increase\"
    labels:
      - \"dependencies\"
      - \"security\""
    fi

    if [ "$MODE" = "python" ] || [ "$MODE" = "both" ]; then
        ECOSYSTEMS="${ECOSYSTEMS}
  - package-ecosystem: \"pip\"
    directory: \"/\"
    schedule:
      interval: \"weekly\"
      day: \"monday\"
    open-pull-requests-limit: 10
    labels:
      - \"dependencies\"
      - \"security\""
    fi

    cat > .github/dependabot.yml <<EOF
# Automated dependency updates
# See: https://docs.github.com/en/code-security/dependabot
version: 2
updates:${ECOSYSTEMS}
EOF

    log "Created .github/dependabot.yml"
}

# ─────────────────────────────────────────────
# Git pre-commit hook
# ─────────────────────────────────────────────
setup_git_hooks() {
    if [ ! -d ".git" ]; then
        warn "Not a git repo; skipping pre-commit hook"
        return
    fi

    mkdir -p .git/hooks

    cat > .git/hooks/pre-commit <<'HOOK'
#!/usr/bin/env bash
# Warn on lockfile changes so they get reviewed intentionally.
# This is a warning, not a block.

LOCKFILES="package-lock.json yarn.lock pnpm-lock.yaml uv.lock requirements.txt Pipfile.lock"
CHANGED=false

for f in $LOCKFILES; do
    if git diff --cached --name-only | grep -q "^${f}$"; then
        echo -e "\033[1;33m[!] Lockfile changed: ${f}\033[0m"
        CHANGED=true
    fi
done

if [ "$CHANGED" = true ]; then
    echo ""
    echo "    Review dependency changes: git diff --cached <lockfile>"
    echo "    Proceeding with commit (warning only)."
    echo ""
fi

exit 0
HOOK

    chmod +x .git/hooks/pre-commit
    log "Installed pre-commit hook (lockfile change warnings)"
}

# ─────────────────────────────────────────────
# .gitignore additions
# ─────────────────────────────────────────────
setup_gitignore() {
    local ENTRIES=(".venv/" "node_modules/" ".env" ".env.local")
    local ADDED=false

    touch .gitignore

    for entry in "${ENTRIES[@]}"; do
        if ! grep -qF "$entry" .gitignore; then
            echo "$entry" >> .gitignore
            ADDED=true
        fi
    done

    if [ "$ADDED" = true ]; then
        log "Updated .gitignore with security-relevant entries"
    fi
}

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────
echo ""
echo "========================================="
echo "  Dependency Security Guardrails Bootstrap"
echo "========================================="
echo ""

case "$MODE" in
    npm)
        setup_npm
        setup_dependabot
        setup_git_hooks
        setup_gitignore
        ;;
    python)
        setup_python
        setup_dependabot
        setup_git_hooks
        setup_gitignore
        ;;
    both)
        setup_npm
        setup_python
        setup_dependabot
        setup_git_hooks
        setup_gitignore
        ;;
    *)
        err "Usage: $0 [npm|python|both]"
        exit 1
        ;;
esac

echo ""
log "Bootstrap complete. Next steps:"
echo ""
echo "  1. Add CI workflow (choose one):"
echo "     a) Reusable: copy examples/reusable-caller.yml to .github/workflows/"
echo "     b) Drop-in:  copy examples/drop-in-workflow.yml to .github/workflows/"
echo ""
echo "  2. Enable Socket.dev on your GitHub repos (free: https://socket.dev)"
echo ""
echo "  3. Review and commit the generated config files"
echo ""
