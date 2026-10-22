#!/bin/sh
set -eu

mkdir -p /tmp/.X11-unix "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99

Xvfb "$DISPLAY" -screen 0 1440x900x24 -ac -nolisten tcp &
fluxbox >/tmp/fluxbox.log 2>&1 &
x11vnc -display "$DISPLAY" -forever -shared -nopw -rfbport 5900 -listen 127.0.0.1 >/tmp/x11vnc.log 2>&1 &

(
  cd /opt/wallet-aps
  while true; do
    dbus-run-session -- ./wallet_aps || true
    sleep 1
  done
) >/tmp/wallet-aps.log 2>&1 &

exec websockify --web=/usr/share/novnc 0.0.0.0:80 localhost:5900
