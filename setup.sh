#!/bin/bash
set -e

echo "==> Setting up Metabase MCP dependencies"

# ── 1. Homebrew ───────────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  echo "==> Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Add brew to PATH for Apple Silicon Macs
  if [[ -f /opt/homebrew/bin/brew ]]; then
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
else
  echo "✓ Homebrew already installed ($(brew --version | head -1))"
fi

# ── 2. Node.js ────────────────────────────────────────────────────────────────
if ! command -v node &>/dev/null; then
  echo "==> Installing Node.js..."
  brew install node
else
  echo "✓ Node.js already installed ($(node --version))"
fi

if ! command -v npx &>/dev/null; then
  echo "ERROR: npx not found even after Node install. Try restarting your terminal."
  exit 1
else
  echo "✓ npx available ($(npx --version))"
fi

# ── 3. Claude Code ────────────────────────────────────────────────────────────
if ! command -v claude &>/dev/null; then
  echo "==> Installing Claude Code..."
  npm install -g @anthropic-ai/claude-code
else
  echo "✓ Claude Code already installed ($(claude --version 2>/dev/null || echo 'version unknown'))"
fi

# ── 4. Register Metabase MCP server ──────────────────────────────────────────
echo ""
echo "==> Registering Metabase MCP server..."
echo "    (You will be prompted for the API key)"
echo ""
read -p "Enter your Metabase API key: " METABASE_API_KEY

claude mcp add metabase \
  --env METABASE_URL=https://metabase-production-6394.up.railway.app \
  --env METABASE_API_KEY="$METABASE_API_KEY" \
  -- npx @cognitionai/metabase-mcp-server --all

# ── 5. Verify ─────────────────────────────────────────────────────────────────
echo ""
echo "==> Verifying connection..."
claude mcp list

echo ""
echo "✓ Setup complete. Open this folder in Claude Code and you're ready to go."
