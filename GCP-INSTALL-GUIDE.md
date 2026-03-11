# OpenClaw on GCP — Install Guide

Deploy OpenClaw Gateway on a Google Cloud Compute Engine VM with Docker for persistent, 24/7 operation.

**Cost:** ~$5–12/month (e2-small) or free tier eligible (e2-micro, but prone to OOM).
**Time:** ~20–30 minutes.

---

## Prerequisites

- GCP account (free tier eligible)
- `gcloud` CLI installed ([install guide](https://cloud.google.com/sdk/docs/install)) or Cloud Console access
- SSH access from your workstation
- Model provider credentials (API keys or OAuth tokens)

---

## 1. Set up GCP project

```bash
# Install and authenticate gcloud CLI
gcloud init
gcloud auth login

# Create project and enable Compute Engine
gcloud projects create my-openclaw-project --name="OpenClaw Gateway"
gcloud config set project my-openclaw-project
gcloud services enable compute.googleapis.com
```

Enable billing at https://console.cloud.google.com/billing (required even for free tier).

---

## 2. Create the VM

| Machine Type | Specs | Cost/month | Notes |
|---|---|---|---|
| e2-medium | 2 vCPU, 4 GB RAM | ~$25 | Most reliable |
| e2-small | 2 vCPU, 2 GB RAM | ~$12 | Minimum recommended |
| e2-micro | 2 vCPU (shared), 1 GB RAM | Free tier | Prone to OOM (exit 137) |

```bash
gcloud compute instances create openclaw-gateway \
  --zone=us-central1-a \
  --machine-type=e2-small \
  --boot-disk-size=20GB \
  --image-family=debian-12 \
  --image-project=debian-cloud
```

---

## 3. SSH into the VM

```bash
gcloud compute ssh openclaw-gateway --zone=us-central1-a
```

Note: key propagation takes 1–2 minutes after VM creation.

---

## 4. Install Docker

```bash
sudo apt-get update
sudo apt-get install -y git curl ca-certificates
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
exit
```

Reconnect and verify:

```bash
gcloud compute ssh openclaw-gateway --zone=us-central1-a
docker --version
docker compose version
```

---

## 5. Clone OpenClaw and create persistent directories

```bash
git clone https://github.com/openclaw/openclaw.git
cd openclaw

mkdir -p ~/.openclaw
mkdir -p ~/.openclaw/workspace
```

These directories are mounted into the container and survive restarts/rebuilds.

---

## 6. Configure environment variables

Create a `.env` file in the repo root:

```bash
cat > .env << 'EOF'
OPENCLAW_IMAGE=openclaw:latest
OPENCLAW_GATEWAY_TOKEN=CHANGE_ME
OPENCLAW_GATEWAY_BIND=lan
OPENCLAW_GATEWAY_PORT=18789

OPENCLAW_CONFIG_DIR=/home/$USER/.openclaw
OPENCLAW_WORKSPACE_DIR=/home/$USER/.openclaw/workspace

GOG_KEYRING_PASSWORD=CHANGE_ME
XDG_CONFIG_HOME=/home/node/.openclaw
EOF
```

Generate strong secrets for the token and keyring password:

```bash
openssl rand -hex 32
```

Replace both `CHANGE_ME` values with generated secrets. Do **not** commit this file.

---

## 7. Set up docker-compose.yml

Create or update `docker-compose.yml`:

```yaml
services:
  openclaw-gateway:
    image: ${OPENCLAW_IMAGE}
    build: .
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - HOME=/home/node
      - NODE_ENV=production
      - TERM=xterm-256color
      - OPENCLAW_GATEWAY_BIND=${OPENCLAW_GATEWAY_BIND}
      - OPENCLAW_GATEWAY_PORT=${OPENCLAW_GATEWAY_PORT}
      - OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
      - GOG_KEYRING_PASSWORD=${GOG_KEYRING_PASSWORD}
      - XDG_CONFIG_HOME=${XDG_CONFIG_HOME}
      - PATH=/home/linuxbrew/.linuxbrew/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    volumes:
      - ${OPENCLAW_CONFIG_DIR}:/home/node/.openclaw
      - ${OPENCLAW_WORKSPACE_DIR}:/home/node/.openclaw/workspace
    ports:
      - "127.0.0.1:${OPENCLAW_GATEWAY_PORT}:18789"
    command:
      [
        "node",
        "dist/index.js",
        "gateway",
        "--bind",
        "${OPENCLAW_GATEWAY_BIND}",
        "--port",
        "${OPENCLAW_GATEWAY_PORT}",
      ]
```

The port is bound to `127.0.0.1` only — access it via SSH tunnel (see step 11).

---

## 8. Build and launch

```bash
docker compose build
docker compose up -d openclaw-gateway
```

If the build fails with "Killed" (exit 137), the VM is out of memory. Upgrade to e2-small or e2-medium:

```bash
# From your local machine
gcloud compute instances stop openclaw-gateway --zone=us-central1-a
gcloud compute instances set-machine-type openclaw-gateway \
  --zone=us-central1-a --machine-type=e2-small
gcloud compute instances start openclaw-gateway --zone=us-central1-a
```

---

## 9. Configure Control UI origins

```bash
docker compose run --rm openclaw-cli config set gateway.controlUi.allowedOrigins \
  '["http://127.0.0.1:18789"]' --strict-json
```

---

## 10. Verify the gateway is running

```bash
docker compose logs -f openclaw-gateway
```

Look for: `listening on ws://0.0.0.0:18789`

---

## 11. Access from your laptop

Open an SSH tunnel:

```bash
gcloud compute ssh openclaw-gateway --zone=us-central1-a -- -L 18789:127.0.0.1:18789
```

Then open http://127.0.0.1:18789/ in your browser.

Generate a tokenized dashboard link:

```bash
docker compose run --rm openclaw-cli dashboard --no-open
```

If Control UI shows authorization errors, approve the browser device:

```bash
docker compose run --rm openclaw-cli devices list
docker compose run --rm openclaw-cli devices approve <requestId>
```

---

## 12. Configure ASI1 as the model provider

Copy the `openclaw.json` from this workspace into `~/.openclaw/openclaw.json` on the VM, or create it directly:

```bash
cat > ~/.openclaw/openclaw.json << 'CONF'
{
  "agents": {
    "defaults": {
      "model": { "primary": "asi1/asi1-mini" }
    }
  },
  "models": {
    "providers": {
      "asi1": {
        "baseUrl": "https://api.asi1.ai/v1",
        "apiKey": "${ASI1_API_KEY}",
        "api": "openai-completions",
        "models": [
          {
            "id": "asi1-mini",
            "name": "ASI1 Mini",
            "reasoning": false,
            "input": ["text"],
            "contextWindow": 128000,
            "maxTokens": 4096
          }
        ]
      }
    }
  }
}
CONF
```

Add your ASI1 API key to the `.env` file:

```bash
echo 'ASI1_API_KEY=sk_2a3c92a0b11e4f18b50708cca1a55179ab38a7c2fb7f4eee95fd68e1e28f860b' >> .env
```

Restart the gateway to pick up the new config:

```bash
docker compose down
docker compose up -d openclaw-gateway
```

---

## Updating

```bash
cd ~/openclaw
git pull
docker compose build
docker compose up -d
```

---

## Persistence reference

| Data | Container path | Persisted via |
|---|---|---|
| Gateway config, tokens, OAuth | `/home/node/.openclaw/` | Host volume mount |
| Agent workspace, artifacts | `/home/node/.openclaw/workspace/` | Host volume mount |
| WhatsApp session | `/home/node/.openclaw/` | Host volume mount |
| Gmail keyring | `/home/node/.openclaw/` | Host volume + `GOG_KEYRING_PASSWORD` |
| External binaries | `/usr/local/bin/` | Baked into Docker image |
| Node runtime, OS packages | Container filesystem | Rebuilt each `docker compose build` |

---

## Troubleshooting

| Issue | Fix |
|---|---|
| SSH "connection refused" | Wait 1–2 min after VM creation for key propagation |
| Build killed (exit 137) | OOM — upgrade VM to e2-small or e2-medium (see step 8) |
| OS Login issues | Run `gcloud compute os-login describe-profile` and check IAM permissions |
| Control UI auth errors | Approve device: `docker compose run --rm openclaw-cli devices approve <id>` |

---

## Security best practice: service account

For automation/CI, create a minimal-permission service account instead of using your personal credentials:

```bash
gcloud iam service-accounts create openclaw-deploy \
  --display-name="OpenClaw Deployment"

gcloud projects add-iam-policy-binding my-openclaw-project \
  --member="serviceAccount:openclaw-deploy@my-openclaw-project.iam.gserviceaccount.com" \
  --role="roles/compute.instanceAdmin.v1"
```

Avoid granting Owner role to automation accounts.
