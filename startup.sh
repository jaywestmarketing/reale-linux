#!/bin/bash
# =============================================================
# RealE Linux — Container Startup
# Copyright (c) Joe Wease, RealE
# =============================================================
set -e

echo ""
echo "  ██████╗ ███████╗ █████╗ ██╗     ███████╗"
echo "  ██╔══██╗██╔════╝██╔══██╗██║     ██╔════╝"
echo "  ██████╔╝█████╗  ███████║██║     █████╗  "
echo "  ██╔══██╗██╔══╝  ██╔══██║██║     ██╔══╝  "
echo "  ██║  ██║███████╗██║  ██║███████╗███████╗"
echo "  ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝╚══════╝"
echo "  RealE Linux — Copyright (c) Joe Wease, RealE"
echo "  reale.one"
echo ""

# ── Load environment ──────────────────────────────────────────
ENV_FILE="/opt/reale-auth/.env"
if [ -f "$ENV_FILE" ]; then
  echo "[startup] Loading environment from $ENV_FILE"
  export $(grep -v '^#' "$ENV_FILE" | xargs)
fi

# ── Clean up stale VNC locks ──────────────────────────────────
echo "[startup] Cleaning VNC locks..."
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true

# ── Start TigerVNC server ─────────────────────────────────────
echo "[startup] Starting TigerVNC on :1 (${VNC_RESOLUTION:-1280x800})..."
vncserver :1 \
  -geometry "${VNC_RESOLUTION:-1280x800}" \
  -depth "${VNC_DEPTH:-24}" \
  -localhost yes \
  -SecurityTypes VncAuth \
  -rfbauth /root/.vnc/passwd \
  -xstartup /root/.vnc/xstartup \
  &

# Wait for VNC to be ready
sleep 3
echo "[startup] VNC server running on :5901"

# ── Start websockify (noVNC bridge) ──────────────────────────
echo "[startup] Starting websockify on port 6080..."
/opt/novnc/utils/websockify/run \
  --web /opt/novnc \
  --heartbeat 30 \
  6080 localhost:5901 \
  &

NOVNC_PID=$!
echo "[startup] noVNC websockify PID: $NOVNC_PID"
sleep 1

# ── Start auth server ─────────────────────────────────────────
echo "[startup] Starting RealE Auth Server on port 3000..."
cd /opt/reale-auth && node server.js &
AUTH_PID=$!
echo "[startup] Auth server PID: $AUTH_PID"
sleep 1

# ── Ensure Nginx dirs ─────────────────────────────────────────
mkdir -p /var/log/nginx /var/lib/nginx/body /run

# ── Start Nginx ───────────────────────────────────────────────
echo "[startup] Starting Nginx on port 80..."
nginx -g "daemon off;" &
NGINX_PID=$!
echo "[startup] Nginx PID: $NGINX_PID"

echo ""
echo "[startup] ✓ All services started"
echo "[startup] → Portal:  http://0.0.0.0:80"
echo "[startup] → Auth API: http://0.0.0.0:3000"
echo "[startup] → VNC:     0.0.0.0:5901"
echo "[startup] → noVNC:   http://0.0.0.0:6080"
echo ""

# ── Keep container alive + handle shutdown ────────────────────
cleanup() {
  echo "[startup] Shutting down services..."
  kill $NGINX_PID $AUTH_PID $NOVNC_PID 2>/dev/null || true
  vncserver -kill :1 2>/dev/null || true
  exit 0
}

trap cleanup SIGTERM SIGINT

# Tail logs to stdout
tail -f /var/log/nginx/error.log /root/.vnc/*.log 2>/dev/null &

# Wait for any process to exit (restart policy handled by RunPod)
wait $NGINX_PID $AUTH_PID $NOVNC_PID
