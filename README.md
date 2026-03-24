# RealE Linux — Browser Desktop Core
**Copyright (c) Joe Wease, RealE · reale.one**

A Debian 12 + XFCE4 browser desktop, delivered via noVNC + TigerVNC,
gated by Solana SPL token ownership.

---

## Stack

| Layer | Technology |
|---|---|
| OS | Debian 12 Bookworm |
| Desktop | XFCE4 |
| VNC Server | TigerVNC |
| Browser Client | noVNC (HTML5) |
| Auth Gate | SPL Token (Solana) + JWT sessions |
| Proxy | Nginx |
| Auth Server | Node.js 20 + Express |

---

## Quick Start (Local Test)

```bash
# 1. Clone / place project
cd reale-linux

# 2. Set environment
cp .env.example .env
# Edit .env — set REALE_TOKEN_MINT and JWT_SECRET at minimum

# 3. Build and run
docker-compose up --build

# 4. Open browser
open http://localhost:8080
```

---

## Deploy to RunPod

### Option A — Docker Image

1. Build and push to Docker Hub or GHCR:
```bash
docker build -t yourdockerhub/reale-linux:latest .
docker push yourdockerhub/reale-linux:latest
```

2. Create a RunPod pod:
   - Image: `yourdockerhub/reale-linux:latest`
   - Expose ports: `80, 3000` (HTTP)
   - Set environment variables from `.env.example`

3. RunPod will give you a public URL like:
   `https://<pod-id>-80.proxy.runpod.net`

### Option B — RunPod Template

Set up a custom template with:
- Container image: your pushed image
- Environment variables: all vars from `.env.example`
- Port 80 exposed as HTTP

---

## SPL Token Setup

### Step 1 — Create your RealE token

```bash
# Install Solana CLI
sh -c "$(curl -sSfL https://release.solana.com/stable/install)"

# Create mint (6 decimals recommended)
spl-token create-token --decimals 6

# Save the mint address — this is your REALE_TOKEN_MINT

# Create token account and mint initial supply
spl-token create-account <MINT_ADDRESS>
spl-token mint <MINT_ADDRESS> 1000000  # 1M tokens
```

### Step 2 — Set env vars

```env
REALE_TOKEN_MINT=<your mint address>
REQUIRED_TOKEN_AMOUNT=1000000   # = 1 token with 6 decimals
```

### Step 3 — Test on devnet first

```env
SOLANA_RPC=https://api.devnet.solana.com
```

---

## Auth Flow

```
Browser → Portal (port 80)
       → Connect wallet (Phantom/Solflare)
       → GET /api/auth/nonce?wallet=... → server returns challenge message
       → Wallet signs challenge message (ed25519)
       → POST /api/auth/verify { wallet, signature, message }
       → Auth server verifies signature proves wallet ownership
       → Auth server checks SPL balance on-chain
       → If OK: issue JWT cookie (reale_session)
       → Redirect to /desktop/vnc.html
       → Nginx auth_request /_auth validates JWT
       → noVNC connects to TigerVNC :5901
       → Full Linux desktop in browser
```

---

## File Structure

```
reale-linux/
├── Dockerfile
├── docker-compose.yml
├── startup.sh              # Service launcher
├── .env.example
├── config/
│   ├── xstartup            # VNC/XFCE launcher
│   └── nginx.conf          # Proxy + auth gate
├── auth/
│   ├── package.json
│   └── server.js           # SPL token gate + JWT
└── portal/
    └── index.html          # Browser login page
```

---

## Ports

| Port | Service | Notes |
|---|---|---|
| 80 | Nginx (portal + noVNC) | Expose publicly |
| 3000 | Auth API | Keep internal if possible |
| 5901 | TigerVNC | Internal only |
| 6080 | noVNC websockify | Internal only |

---

## Phase 2 Roadmap

- [x] Wallet signature verification (prove ownership)
- [ ] Per-session resource limits (CPU/RAM quotas)
- [ ] Multi-user isolation (one container per session)
- [ ] Persistent user home directories (Render/S3 volumes)
- [ ] Admin dashboard (session management, token analytics)
- [ ] RealE Pay integration for token purchase flow
- [ ] Custom XFCE theme (RealE branding)

---

*All rights reserved. Software licensed to Joe Wease, RealE.*
