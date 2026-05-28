#!/usr/bin/env bash
set -eu

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}=============================================${NC}"
echo -e "${CYAN}  Claude Code + DeepSeek One-Click Install${NC}"
echo -e "${CYAN}=============================================${NC}"
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CC_CONFIG_DIR="$HOME/.claude"
OS="$(uname -s)"

# -- 1. Get API Key --

echo -e "[1/9] Configure DeepSeek API Key"
echo "(Register and create at platform.deepseek.com, then paste here)"
echo ""
read -r -p "Enter DeepSeek API Key: " DEEPSEEK_KEY
if [ -z "$DEEPSEEK_KEY" ]; then
    echo -e "${RED}[Error] API Key cannot be empty${NC}"
    exit 1
fi
echo -e "  API Key set: ${DEEPSEEK_KEY:0:8}****"

# -- 2. Get License Key --

echo ""
echo -e "[2/9] Configure License Key"
echo "(Obtained after purchase, looks like DS-CNDS-XXXX-XXXX)"
echo ""
read -r -p "Enter License Key: " LICENSE_KEY
if [ -z "$LICENSE_KEY" ]; then
    echo -e "${RED}[Error] License Key cannot be empty${NC}"
    exit 1
fi
echo -e "  License Key set: ${LICENSE_KEY:0:8}****"

# -- 3. Validate License (one machine one code) --

echo ""
echo "[3/9] Validating License..."

# Collect machine fingerprint
case "$OS" in
    Darwin)
        MACHINE_ID=$(ioreg -d2 -c IOPlatformExpertDevice 2>/dev/null | awk -F\" '/IOPlatformUUID/{print $(NF-1); exit}' || echo "")
        ;;
    Linux)
        if [ -f /etc/machine-id ]; then
            MACHINE_ID=$(cat /etc/machine-id 2>/dev/null || echo "")
        elif [ -f /var/lib/dbus/machine-id ]; then
            MACHINE_ID=$(cat /var/lib/dbus/machine-id 2>/dev/null || echo "")
        else
            MACHINE_ID=""
        fi
        ;;
    *)
        echo -e "${RED}[Error] Unsupported OS: ${OS}${NC}"
        exit 1
        ;;
esac

if [ -z "$MACHINE_ID" ]; then
    echo -e "${RED}[Error] Cannot get machine identifier${NC}"
    exit 1
fi
echo "  Machine ID: ${MACHINE_ID:0:16}****"

# Query Supabase for license
SUPABASE_URL="https://onzyjumuidejsxzgzwit.supabase.co"
SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9uenlqdW11aWRlanN4emd6d2l0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1NTU0NDIsImV4cCI6MjA5NTEzMTQ0Mn0.DuFex3z0ID_BFNTpYkbd7jBeoFwmThXge98H0v63Xo8"

LICENSE_DATA=$(curl -s --connect-timeout 10 \
    "${SUPABASE_URL}/rest/v1/licenses?license_key=eq.${LICENSE_KEY}&select=*" \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_ANON_KEY}")

if [ -z "$LICENSE_DATA" ] || [ "$LICENSE_DATA" = "[]" ]; then
    echo -e "${RED}[Error] License Key not found${NC}"
    exit 1
fi

# Parse fields from license record
_parse_field() {
    _field="$1"
    _val=$(echo "$LICENSE_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0].get('${_field}',''))" 2>/dev/null || \
           echo "$LICENSE_DATA" | python -c "import sys,json; d=json.load(sys.stdin); print(d[0].get('${_field}',''))" 2>/dev/null || \
           echo "")
    echo "$_val"
}

LIC_STATUS=$(_parse_field "status")
LIC_EXPIRES=$(_parse_field "expires_at")
LIC_MACHINE=$(_parse_field "fingerprint")

# Check revoked
if [ "$LIC_STATUS" = "revoked" ]; then
    echo -e "${RED}[Error] License Key has been revoked${NC}"
    exit 1
fi

# Check expired status
if [ "$LIC_STATUS" = "expired" ]; then
    echo -e "${RED}[Error] License Key has expired${NC}"
    exit 1
fi

# Check expires_at date (ISO date string comparison)
if [ -n "$LIC_EXPIRES" ] && [ "$LIC_EXPIRES" != "None" ]; then
    NOW_ISO=$(date -u +"%Y-%m-%d")
    EXPIRES_DATE=$(echo "$LIC_EXPIRES" | sed 's/T.*//')
    if [[ "$EXPIRES_DATE" < "$NOW_ISO" ]]; then
        echo -e "${RED}[Error] License Key has expired (${EXPIRES_DATE})${NC}"
        exit 1
    fi
fi

# Check machine binding (one machine one code)
# "active" + no fingerprint → first activation, proceed
# "activated" + fingerprint matches → re-install on same machine, OK
# "activated" + fingerprint mismatch → reject
ALREADY_ACTIVATED=false
if [ "$LIC_STATUS" = "activated" ]; then
    if [ -n "$LIC_MACHINE" ] && [ "$LIC_MACHINE" != "None" ]; then
        if [ "$LIC_MACHINE" != "$MACHINE_ID" ]; then
            echo -e "${RED}[Error] License Key has been bound to another device${NC}"
            exit 1
        fi
        ALREADY_ACTIVATED=true
    fi
fi

echo -e "  License validated"

# -- 4. Update DB License --

echo ""
echo "[4/9] Activating License..."

if [ "$ALREADY_ACTIVATED" = true ]; then
    ACTIVATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # Re-install on same machine: only update actived_at
    UPDATE_BODY="{\"actived_at\":\"${ACTIVATED_AT}\"}"
else
    ACTIVATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # First activation: bind fingerprint + set status to activated
    UPDATE_BODY="{\"fingerprint\":\"${MACHINE_ID}\",\"actived_at\":\"${ACTIVATED_AT}\",\"status\":\"activated\"}"
fi

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 \
    -X PATCH \
    "${SUPABASE_URL}/rest/v1/licenses?license_key=eq.${LICENSE_KEY}" \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=minimal" \
    -d "${UPDATE_BODY}")

if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "200" ]; then
    echo -e "  License activated"
else
    echo -e "  ${YELLOW}[Warning] License activation record failed (HTTP ${HTTP_CODE}), continuing...${NC}"
fi

# -- 5. Check/Install Node.js --

echo ""
echo -e "[5/9] Checking Node.js..."

if command -v node &>/dev/null; then
    NODE_VERSION=$(node -v)
    echo -e "  Node.js installed: ${GREEN}${NODE_VERSION}${NC}"
else
    echo "  Node.js not found, installing..."

    if [ "$OS" = "Darwin" ]; then
        NODE_PKG_URL="https://registry.npmmirror.com/-/binary/node/v20.18.1/node-v20.18.1.pkg"
        NODE_PKG="/tmp/node-v20.18.1.pkg"
        echo "  Downloading Node.js (mirror, ~60MB)..."
        if curl -fsSL --connect-timeout 10 "$NODE_PKG_URL" -o "$NODE_PKG"; then
            echo "  Installing Node.js (admin password may be needed)..."
            sudo installer -pkg "$NODE_PKG" -target /
            rm -f "$NODE_PKG"
        fi

        if ! command -v node &>/dev/null; then
            if command -v brew &>/dev/null; then
                echo "  pkg install failed, trying Homebrew..."
                brew install node@20
            else
                echo "  Installing Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                if [ -f /opt/homebrew/bin/brew ]; then
                    eval "$(/opt/homebrew/bin/brew shellenv)"
                elif [ -f /usr/local/bin/brew ]; then
                    eval "$(/usr/local/bin/brew shellenv)"
                fi
                brew install node@20
            fi
        fi
    elif [ "$OS" = "Linux" ]; then
        if command -v apt-get &>/dev/null; then
            curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
            sudo apt-get install -y nodejs
        elif command -v yum &>/dev/null; then
            curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo -E bash -
            sudo yum install -y nodejs
        elif command -v dnf &>/dev/null; then
            curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo -E bash -
            sudo dnf install -y nodejs
        else
            echo -e "${RED}[Error] Cannot detect package manager. Install Node.js manually: https://nodejs.org${NC}"
            exit 1
        fi
    fi

    if ! command -v node &>/dev/null; then
        echo -e "${RED}[Error] Node.js install failed. Manual install: https://nodejs.org${NC}"
        exit 1
    fi
    echo -e "  Node.js install done: ${GREEN}$(node -v)${NC}"
fi

# Check npm mirror (China)
if ! curl -s --connect-timeout 3 https://registry.npmjs.org >/dev/null 2>&1; then
    echo "  Network restricted, switching to npmmirror..."
    npm config set registry https://registry.npmmirror.com
fi

# -- 6. Check/Install Git --

echo ""
echo -e "[6/9] Checking Git..."

if command -v git &>/dev/null; then
    echo -e "  Git installed: ${GREEN}$(git --version)${NC}"
else
    echo "  Git not found, installing..."

    if [ "$OS" = "Darwin" ]; then
        xcode-select --install 2>/dev/null || true
        if ! command -v git &>/dev/null; then
            echo -e "  ${YELLOW}[Warning] Git install failed, skip${NC}"
        else
            echo -e "  Git install done: ${GREEN}$(git --version)${NC}"
        fi
    elif [ "$OS" = "Linux" ]; then
        if command -v apt-get &>/dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y git
        elif command -v yum &>/dev/null; then
            sudo yum install -y git
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y git
        else
            echo -e "${YELLOW}[Warning] Cannot auto-install Git: https://git-scm.com${NC}"
        fi
        if ! command -v git &>/dev/null; then
            echo -e "${YELLOW}[Warning] Git install failed, skip${NC}"
        else
            echo -e "  Git install done: ${GREEN}$(git --version)${NC}"
        fi
    fi
fi

# -- 7. Install Claude Code --

echo ""
echo "[7/9] Installing Claude Code CLI..."

if [ "$OS" = "Darwin" ] && [ ! -w /usr/local/lib/node_modules ] 2>/dev/null; then
    echo "  Admin password needed for npm global install..."
    sudo npm install -g @anthropic-ai/claude-code || {
        echo -e "${RED}[Error] Claude Code install failed${NC}"
        exit 1
    }
else
    npm install -g @anthropic-ai/claude-code || {
        echo -e "${RED}[Error] Claude Code install failed${NC}"
        exit 1
    }
fi
echo "  Claude Code install done"

# -- 8. Write Claude Code config --

echo ""
echo "[8/9] Writing Claude Code config..."

mkdir -p "$CC_CONFIG_DIR"

echo '{"hasCompletedOnboarding": true}' > "$HOME/.claude.json"
echo "  Created: $HOME/.claude.json"

cat > "$CC_CONFIG_DIR/settings.json" << EOF
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
    "ANTHROPIC_API_KEY": "${DEEPSEEK_KEY}",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "deepseek-v4-pro[1m]",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "deepseek-v4-pro[1m]",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "deepseek-v4-pro[1m]",
    "ANTHROPIC_MODEL": "deepseek-v4-pro[1m]",
    "API_TIMEOUT_MS": "600000",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
  }
}
EOF

echo "  Config written: $CC_CONFIG_DIR/settings.json"

# -- 9. Verify --

echo ""
echo "[9/9] Verifying installation..."

if curl -s -X POST https://api.deepseek.com/anthropic/v1/messages \
    -H "Content-Type: application/json" \
    -H "x-api-key: ${DEEPSEEK_KEY}" \
    -d '{"model":"deepseek-v4-pro[1m]","max_tokens":10,"messages":[{"role":"user","content":"Reply OK"}]}' \
    --connect-timeout 30 >/dev/null 2>&1; then
    echo -e "  ${GREEN}Connectivity test passed${NC}"
else
    echo -e "  ${YELLOW}Connectivity test failed, check API Key${NC}"
    echo "  Manual test: claude -p 'Reply OK'"
fi

echo ""
echo -e "${CYAN}=============================================${NC}"
echo -e "${CYAN}  Installation Complete!${NC}"
echo -e "${CYAN}=============================================${NC}"
echo ""
echo "  Usage:"
echo "    claude                      Start Claude Code"
echo ""
