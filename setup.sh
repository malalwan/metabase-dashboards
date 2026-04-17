#!/bin/bash
set -e

echo ""
echo "=========================================="
echo "  Metabase MCP — Full Setup for Mac"
echo "=========================================="
echo ""

# ── 1. Homebrew ───────────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  echo "==> Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Add brew to PATH (Apple Silicon)
  if [[ -f /opt/homebrew/bin/brew ]]; then
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
else
  echo "✓ Homebrew ($(brew --version | head -1))"
fi

# ── 2. Git ────────────────────────────────────────────────────────────────────
if ! command -v git &>/dev/null; then
  echo "==> Installing Git..."
  brew install git
else
  echo "✓ Git ($(git --version))"
fi

# ── 3. GitHub CLI (gh) ────────────────────────────────────────────────────────
if ! command -v gh &>/dev/null; then
  echo "==> Installing GitHub CLI..."
  brew install gh
else
  echo "✓ GitHub CLI ($(gh --version | head -1))"
fi

# ── 4. Authenticate with GitHub ───────────────────────────────────────────────
if ! gh auth status &>/dev/null; then
  echo ""
  echo "==> Log in to GitHub (a browser window will open)..."
  gh auth login --web -h github.com
else
  echo "✓ GitHub authenticated ($(gh auth status 2>&1 | grep 'Logged in' | xargs))"
fi

# ── 5. Clone the repo ─────────────────────────────────────────────────────────
REPO="malalwan/metabase-dashboards"
TARGET="$HOME/metabase-dashboards"

if [[ -d "$TARGET/.git" ]]; then
  echo "✓ Repo already cloned at $TARGET — pulling latest..."
  git -C "$TARGET" pull
else
  echo "==> Cloning $REPO..."
  gh repo clone "$REPO" "$TARGET"
fi

cd "$TARGET"
echo "✓ Working directory: $(pwd)"

# ── 6. Node.js ────────────────────────────────────────────────────────────────
if ! command -v node &>/dev/null; then
  echo "==> Installing Node.js..."
  brew install node
else
  echo "✓ Node.js ($(node --version))"
fi

if ! command -v npx &>/dev/null; then
  echo "ERROR: npx not found after Node install. Please restart your terminal and re-run this script."
  exit 1
fi

# ── 7. Claude Code ────────────────────────────────────────────────────────────
if ! command -v claude &>/dev/null; then
  echo "==> Installing Claude Code..."
  npm install -g @anthropic-ai/claude-code
else
  echo "✓ Claude Code ($(claude --version 2>/dev/null || echo 'installed'))"
fi

# ── 8. Register Metabase MCP server ───────────────────────────────────────────
echo ""
echo "==> Registering Metabase MCP server..."
read -p "Enter the Metabase API key (ask Mayank): " METABASE_API_KEY
echo ""

claude mcp add metabase \
  --env METABASE_URL=https://metabase-production-6394.up.railway.app \
  --env METABASE_API_KEY="$METABASE_API_KEY" \
  -- npx @cognitionai/metabase-mcp-server --all

# ── 9. Verify ─────────────────────────────────────────────────────────────────
echo ""
echo "==> Verifying MCP connection..."
claude mcp list

echo ""
echo "=========================================="
echo "  ✓ All done!"
echo ""
echo "  Next steps:"
echo "  1. Open Claude Code: claude"
echo "  2. Navigate to: $TARGET"
echo "  3. Start building dashboards!"
echo "=========================================="
