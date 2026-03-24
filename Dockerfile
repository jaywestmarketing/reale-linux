# =============================================================
# RealE Linux — Browser Desktop Core
# Copyright (c) Joe Wease, RealE
# Debian 12 + XFCE4 + TigerVNC + noVNC + SPL Token Gate
# =============================================================

FROM debian:bookworm-slim

LABEL maintainer="Joe Wease <reale.one>"
LABEL description="RealE Linux — Browser Desktop Core"
LABEL version="1.0.0"

ENV DEBIAN_FRONTEND=noninteractive
ENV VNC_PORT=5901
ENV NOVNC_PORT=6080
ENV AUTH_PORT=3000
ENV DISPLAY=:1
ENV VNC_RESOLUTION=1280x800
ENV VNC_DEPTH=24
ENV HOME=/root
ENV USER=root

# ── System packages ──────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core tools
    curl wget ca-certificates gnupg2 sudo lsb-release \
    git vim nano net-tools procps htop \
    # VNC
    tigervnc-standalone-server tigervnc-common \
    # noVNC dependencies
    python3 python3-pip python3-websockify \
    # XFCE desktop
    xfce4 xfce4-terminal xfce4-taskmanager \
    xfce4-screenshooter xfce4-notifyd \
    mousepad thunar \
    # Fonts & themes
    fonts-dejavu-core fonts-liberation \
    gtk2-engines-murrine adwaita-icon-theme \
    # App basics
    firefox-esr \
    # Nginx
    nginx \
    # Node.js setup dep
    gnupg2 \
    # Misc
    dbus-x11 at-spi2-core \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js 20 LTS ───────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# ── noVNC ────────────────────────────────────────────────────
RUN git clone --depth 1 https://github.com/novnc/noVNC.git /opt/novnc \
    && git clone --depth 1 https://github.com/novnc/websockify /opt/novnc/utils/websockify \
    && ln -s /opt/novnc/vnc.html /opt/novnc/index.html

# ── VNC password ─────────────────────────────────────────────
RUN mkdir -p /root/.vnc \
    && echo "realelinux" | vncpasswd -f > /root/.vnc/passwd \
    && chmod 600 /root/.vnc/passwd

# ── VNC xstartup ─────────────────────────────────────────────
COPY config/xstartup /root/.vnc/xstartup
RUN chmod +x /root/.vnc/xstartup

# ── Auth server (Node.js SPL token gate) ─────────────────────
COPY auth/ /opt/reale-auth/
RUN cd /opt/reale-auth && npm install --omit=dev

# ── Portal (login page) ───────────────────────────────────────
COPY portal/ /var/www/reale-portal/

# ── Nginx config ─────────────────────────────────────────────
COPY config/nginx.conf /etc/nginx/nginx.conf

# ── Startup script ───────────────────────────────────────────
COPY startup.sh /opt/startup.sh
RUN chmod +x /opt/startup.sh

# ── Expose ports ─────────────────────────────────────────────
# 80   → Nginx (portal + proxied noVNC)
# 3000 → Auth API
# 5901 → VNC (internal)
# 6080 → noVNC websocket (internal)
EXPOSE 80 3000 5901 6080

CMD ["/opt/startup.sh"]
