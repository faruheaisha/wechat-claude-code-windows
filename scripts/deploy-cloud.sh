#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# wechat-claude-code — Cloud Deployment Script
# =============================================================================
#
# One-click deployment for Ubuntu 22.04+ VPS.
# Installs Node.js, Claude Code CLI, clones the project, and sets up
# a systemd service for 24/7 operation.
#
# Usage:
#   curl -fsSL <raw-github-url>/scripts/deploy-cloud.sh | bash
#
# Prerequisites:
#   - Ubuntu 22.04+ VPS (e.g. DigitalOcean $4/mo droplet)
#   - Root or sudo access
#   - GitHub Student Pack activated with DigitalOcean $200 credit
#
# Post-install:
#   1. Bind WeChat:   node /opt/wechat-claude-code/dist/main.js setup
#   2. Auth Claude:   su - wcc-bridge -c 'claude'
#   3. Start bridge:  systemctl start wechat-bridge
# =============================================================================

echo "=============================================="
echo "  wechat-claude-code Cloud Deployment"
echo "=============================================="

# ── Config ───────────────────────────────────────────────────────────────────
REPO_URL="https://github.com/faruheaisha/wechat-claude-code-windows.git"
INSTALL_DIR="/opt/wechat-claude-code"
NODE_VERSION="22"
SERVICE_USER="wcc-bridge"

# ── 1. System packages ───────────────────────────────────────────────────────
echo "[1/6] Installing system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl git build-essential python3

# ── 2. Install Node.js ─────────────────────────────────────────────────────
echo "[2/6] Installing Node.js $NODE_VERSION LTS..."
curl -fsSL "https://deb.nodesource.com/setup_$NODE_VERSION.x" | bash - >/dev/null
apt-get install -y -qq nodejs
echo "  Node.js: $(node --version)"
echo "  npm:     $(npm --version)"

# ── 3. Clone repo ──────────────────────────────────────────────────────────
echo "[3/6] Cloning repository..."
if [ -d "$INSTALL_DIR" ]; then
  cd "$INSTALL_DIR" && git pull
else
  git clone "$REPO_URL" "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"

# ── 4. Install dependencies + build ────────────────────────────────────────
echo "[4/6] Installing dependencies (including build tools)..."
npm install
echo "  Build: OK"

# ── 5. Install Claude Code CLI ────────────────────────────────────────────
echo "[5/6] Installing Claude Code CLI..."
npm install -g @anthropic-ai/claude-code
echo "  claude: $(claude --version 2>/dev/null || echo 'installed')"

# ── 6. Setup systemd service ──────────────────────────────────────────────
echo "[6/6] Configuring systemd service..."

# Create a dedicated system user for the bridge service
if ! id "$SERVICE_USER" &>/dev/null; then
  useradd -r -s /usr/sbin/nologin -m -d "/var/lib/$SERVICE_USER" "$SERVICE_USER"
fi
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"

# Write systemd unit
cat > /etc/systemd/system/wechat-bridge.service << 'SERVICE'
[Unit]
Description=WeChat Claude Code Bridge
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=wcc-bridge
WorkingDirectory=/opt/wechat-claude-code
ExecStart=/usr/bin/node /opt/wechat-claude-code/dist/main.js start
Restart=always
RestartSec=10
Environment=NODE_ENV=production
StandardOutput=append:/var/log/wechat-bridge-stdout.log
StandardError=append:/var/log/wechat-bridge-stderr.log

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable wechat-bridge

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "=============================================="
echo "  Deployment complete!"
echo "=============================================="
echo ""
echo "Next steps:"
echo ""
echo "  1. Bind WeChat account:"
echo "     node $INSTALL_DIR/dist/main.js setup"
echo ""
echo "  2. Authenticate Claude Code:"
echo "     su - $SERVICE_USER -c 'claude'"
echo ""
echo "  3. Start the service:"
echo "     systemctl start wechat-bridge"
echo ""
echo "  4. Check status:"
echo "     systemctl status wechat-bridge"
echo ""
echo "  5. View live logs:"
echo "     journalctl -u wechat-bridge -f"
echo ""
echo "=============================================="
