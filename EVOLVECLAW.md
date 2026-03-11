# OpenClaw Gateway Deployments

Two OpenClaw Gateway instances running on GCP in the same project.

## Infrastructure

| Field | KennyKlaw | EvolveClaw |
|-------|-----------|------------|
| **Instance** | `kennyklaw` | `evolveclaw` |
| **Project** | `fetch-coder` | `fetch-coder` |
| **Zone** | `us-central1-a` | `us-central1-a` |
| **Machine type** | `e2-medium` (2 vCPU, 4 GB) | `e2-medium` (2 vCPU, 4 GB) |
| **Boot disk** | 20 GB, Debian 12 | 20 GB, Debian 12 |
| **External IP** | `136.119.195.121` | `34.123.5.121` |
| **Local tunnel port** | `18789` | `18790` |
| **Swap** | 2 GB (`/swapfile`) | 2 GB (`/swapfile`) |

## Services

### OpenClaw Gateway (Docker)

- **Image:** `openclaw:latest` (built from `~/openclaw` on the VM)
- **Container:** `openclaw-openclaw-gateway-1`
- **Port:** 18789 (inside container and host)
- **Model:** `asi1/asi1-mini` via `https://api.asi1.ai/v1`
- **Gateway mode:** `local`
- **Password protected:** Yes (`OPENCLAW_GATEWAY_PASSWORD` in `.env`)
- **Config:** `~/.openclaw/openclaw.json`
- **Compose file:** `~/openclaw/docker-compose.yml`

### Claude Code

- **Installed globally:** `npm install -g @anthropic-ai/claude-code` (host + container)
- **Version:** 2.1.72
- **Auth:** Authenticated via web Claude account (credentials copied into container)
- **Node.js:** v22.22.1 (host)
- **ACP/acpx:** Working — `@zed-industries/claude-agent-acp` installed in container
- **acpx symlink:** `/usr/local/bin/acpx` → `/app/extensions/acpx/node_modules/.bin/acpx` (created manually, lost on container rebuild)
- **acpx config:** `/home/node/.acpx/config.json` — maps `claude-code` and `claudecode` agent aliases to the claude adapter
- **Container packages:** `@anthropic-ai/claude-code` + `@zed-industries/claude-agent-acp` (installed as root in container)

## Access

### SSH Tunnel (Control UI)

**KennyKlaw:**
```bash
gcloud compute ssh kennyklaw --zone=us-central1-a --project=fetch-coder -- -N -L 18789:127.0.0.1:18789
```
Then open: `http://127.0.0.1:18789/`

**EvolveClaw:**
```bash
gcloud compute ssh evolveclaw --zone=us-central1-a --project=fetch-coder -- -N -L 18790:127.0.0.1:18789
```
Then open: `http://127.0.0.1:18790/#password=evolveclaw2026`

### Direct SSH

```bash
gcloud compute ssh kennyklaw --zone=us-central1-a --project=fetch-coder
gcloud compute ssh evolveclaw --zone=us-central1-a --project=fetch-coder
```

## Secrets

| Secret | Location |
|--------|----------|
| Gateway token | `~/openclaw/.env` → `OPENCLAW_GATEWAY_TOKEN` |
| Gateway password | `~/openclaw/.env` → `OPENCLAW_GATEWAY_PASSWORD` |
| Keyring | `~/openclaw/.env` → `GOG_KEYRING_PASSWORD` |
| ASI1 API key | `~/openclaw/.env` → `ASI1_API_KEY` (same as KennyKlaw) |

## Key Files on VM

```
~/openclaw/                  # OpenClaw repo clone
~/openclaw/.env              # Docker env vars (secrets)
~/openclaw/docker-compose.yml # Compose config (modified: added ASI1_API_KEY, OPENCLAW_GATEWAY_PASSWORD)
~/.openclaw/openclaw.json    # Gateway runtime config (owned by uid 1000)
~/.openclaw/workspace/       # Agent workspace
/swapfile                    # 2 GB swap (not persistent across reboot unless added to fstab)
```

## Common Operations

### Restart gateway
```bash
cd ~/openclaw && docker compose restart openclaw-gateway
```

### Full restart (down + up)
```bash
cd ~/openclaw && docker compose down && docker compose up -d openclaw-gateway
```

### View logs
```bash
docker logs openclaw-openclaw-gateway-1 --tail 50
```

### Rebuild image (after git pull)
```bash
cd ~/openclaw && git pull && docker build -t openclaw:latest . && docker compose down && docker compose up -d openclaw-gateway
```

### Test message through gateway (with Claude Code / ACP)
```bash
TOKEN=$(grep OPENCLAW_GATEWAY_TOKEN ~/openclaw/.env | cut -d= -f2)
docker exec -e HOME=/home/node -e OPENCLAW_GATEWAY_TOKEN=$TOKEN openclaw-openclaw-gateway-1 \
  node dist/index.js agent --message "use claude code to answer: what is 2+2?" --agent main
```

### Test ACP directly (acpx)
```bash
docker exec -e HOME=/home/node openclaw-openclaw-gateway-1 \
  /app/extensions/acpx/node_modules/.bin/acpx --verbose --approve-all claude exec "say hello"
```

### Re-enable swap after VM reboot
```bash
sudo swapon /swapfile
```

To make swap persistent, add to `/etc/fstab`:
```
/swapfile none swap sw 0 0
```

## Deployment Notes

- **e2-small OOMs** during Docker build — e2-medium is the minimum.
- **2 GB swap** was added to prevent thrashing during the TypeScript compilation step (`pnpm build:docker`). Without swap the VM becomes unresponsive.
- The Dockerfile no longer needs the `npm link` permission fix (uses `ln -sf` now).
- `ASI1_API_KEY` and `OPENCLAW_GATEWAY_PASSWORD` were manually added to `docker-compose.yml` environment section — they are not in the upstream compose file.
- `~/.openclaw` ownership must be uid `1000:1000` (container's `node` user).
- The OpenClaw setup wizard can mangle the provider config (renamed `asi1` → `asi1-mini`, model `asi1-mini` → `asi1-mini-mini`). If timeouts occur, verify `openclaw.json` has correct provider/model names.
- **Claude Code hangs fix (two parts):**
  1. `~/.claude.json` (host) and `/home/node/.claude.json` (container) must have `hasCompletedOnboarding: true` and `hasTrustDialogAccepted: true` in the projects section for `/app`, `/home/node`, and `/home/node/.openclaw/workspace`.
  2. `~/.claude/settings.json` (host) and `/home/node/.claude/settings.json` (container) must have `disabledRemoteMcpServers` listing all remote MCP server IDs from the account. Without this, Claude Code hangs trying to connect to remote MCP servers (Gmail, Calendar, agentverse) via SSE. The cached feature flag `tengu_claudeai_mcp_connectors` gets overwritten by the API on every startup, so `settings.json` is the only durable fix.
- **After re-auth:** Re-apply `hasTrustDialogAccepted: true` in `.claude.json` on both host and container. The `settings.json` fix persists across re-auth.
- **ACP agent ID fix:** The `openclaw.json` must list `"claude"`, `"claude-code"`, and `"claudecode"` in `acp.allowedAgents` because ASI1-mini may use any of these variations. The `~/.acpx/config.json` must map `claude-code` and `claudecode` to `npx -y @zed-industries/claude-agent-acp@^0.21.0` (acpx only has `claude` as a built-in alias). Without this, `sessions_spawn` fails with "ACP agent not allowed by policy" or "acpx exited with code 1".
- **ACP permission mode:** The acpx plugin must have `config.permissionMode: "approve-all"` in `openclaw.json` under `plugins.entries.acpx`. Without this, Claude Code's file writes and command execution are blocked with "Permission denied by ACP runtime" in non-interactive sessions.
- **Container rebuild checklist:** After `docker compose build`, re-apply these manual fixes:
  1. `ln -sf /app/extensions/acpx/node_modules/.bin/acpx /usr/local/bin/acpx`
  2. `mkdir -p /home/node/.acpx && cat > /home/node/.acpx/config.json` with the agent aliases
  3. Re-apply `.claude.json` onboarding/trust fixes
  4. Verify `/home/node/.claude/settings.json` still has `disabledRemoteMcpServers`

---

## ACP Setup Script (for new or rebuilt containers)

Run these commands inside the container after a fresh build or rebuild. Replace `INSTANCE` with `kennyklaw` or `evolveclaw`.

```bash
# SSH into the VM
gcloud compute ssh INSTANCE --zone=us-central1-a --project=fetch-coder

# 1. Install Claude Code and claude-agent-acp (as root inside container)
docker exec -u root openclaw-openclaw-gateway-1 bash -c '
npm install -g @anthropic-ai/claude-code @zed-industries/claude-agent-acp
ln -sf /app/extensions/acpx/node_modules/.bin/acpx /usr/local/bin/acpx
'

# 2. Create acpx agent aliases config
docker exec openclaw-openclaw-gateway-1 bash -c '
mkdir -p /home/node/.acpx
cat > /home/node/.acpx/config.json << EOF
{
  "agents": {
    "claude-code": { "command": "npx -y @zed-industries/claude-agent-acp@^0.21.0" },
    "claudecode": { "command": "npx -y @zed-industries/claude-agent-acp@^0.21.0" }
  }
}
EOF
'

# 3. Create Claude Code settings (disable remote MCP servers)
docker exec openclaw-openclaw-gateway-1 bash -c '
mkdir -p /home/node/.claude
cat > /home/node/.claude/settings.json << EOF
{
  "mcpServers": {},
  "disabledRemoteMcpServers": [
    "mcpsrv_01Rw7JQuvmdkMbP5coCeaZRm",
    "mcpsrv_01BLtZittTchf5EVhECySrKZ",
    "mcpsrv_012MZdsHzMNhMfqoahrDDom8",
    "mcpsrv_018QaHjKCo6LJD24BY5CD14L",
    "mcpsrv_013BdeAwdxLzZjMGrwGkQv1c"
  ]
}
EOF
'

# 4. Create .claude.json with onboarding + trust dialog
docker exec openclaw-openclaw-gateway-1 bash -c '
cat > /home/node/.claude.json << EOF
{
  "hasCompletedOnboarding": true,
  "lastOnboardingVersion": "2.1.72",
  "projects": {
    "/app": { "allowedTools": [], "mcpServers": {}, "hasTrustDialogAccepted": true },
    "/home/node": { "allowedTools": [], "mcpServers": {}, "hasTrustDialogAccepted": true },
    "/home/node/.openclaw/workspace": { "allowedTools": [], "mcpServers": {}, "hasTrustDialogAccepted": true }
  }
}
EOF
'

# 5. Copy Claude credentials (from an authenticated instance)
# Get credentials from evolveclaw (or any instance with valid OAuth):
#   gcloud compute ssh evolveclaw --zone=us-central1-a --project=fetch-coder --command='
#     docker exec openclaw-openclaw-gateway-1 cat /home/node/.claude/.credentials.json'
# Then write them into the target container:
docker exec openclaw-openclaw-gateway-1 bash -c '
cat > /home/node/.claude/.credentials.json << EOF
{"claudeAiOauth":{"accessToken":"YOUR_TOKEN","refreshToken":"YOUR_REFRESH","expiresAt":TIMESTAMP,"scopes":["user:inference","user:mcp_servers","user:profile","user:sessions:claude_code"],"subscriptionType":"max","rateLimitTier":"default_claude_max_20x"}}
EOF
'

# 6. Restart gateway to pick up changes
cd ~/openclaw && docker compose restart openclaw-gateway

# 7. Verify
docker exec -e HOME=/home/node openclaw-openclaw-gateway-1 \
  timeout 60 /usr/local/bin/acpx --verbose --approve-all claude exec "say hello"
```

### Test through gateway CLI

```bash
TOKEN=$(grep OPENCLAW_GATEWAY_TOKEN ~/openclaw/.env | cut -d= -f2)
docker exec -e HOME=/home/node -e OPENCLAW_GATEWAY_TOKEN=$TOKEN openclaw-openclaw-gateway-1 \
  timeout 180 node dist/index.js agent --message "use claude code to answer: what is 2+2?" --agent main
```
