#!/usr/bin/env bash
set -euo pipefail

GREEN="\033[1;32m"; YELLOW="\033[1;33m"; RED="\033[1;31m"; NC="\033[0m"
need_cmd(){ command -v "$1" >/dev/null 2>&1; }
sudo_wrap(){ if [[ $EUID -ne 0 ]]; then sudo "$@"; else "$@"; fi; }

ensure_kbd(){
  if need_cmd setleds; then return; fi
  echo -e "${YELLOW}Installing 'kbd'...${NC}"
  if need_cmd apt; then sudo_wrap apt update -y && sudo_wrap apt install -y kbd
  elif need_cmd dnf; then sudo_wrap dnf install -y kbd
  elif need_cmd pacman; then sudo_wrap pacman -Sy --noconfirm kbd
  elif need_cmd zypper; then sudo_wrap zypper install -y kbd
  else echo -e "${RED}Please install 'kbd' manually.${NC}"
  fi
}

install_core(){
  ensure_kbd
  sudo_wrap tee /usr/local/bin/scrolllockd.sh >/dev/null <<'SH'
#!/usr/bin/env bash
set -euo pipefail

have(){ command -v "$1" >/dev/null 2>&1; }
log(){ if have logger; then logger -t keylights "$*"; else printf 'keylights: %s\n' "$*"; fi; }
SETLEDS="$(command -v setleds || echo /usr/bin/setleds)"

apply_led(){
  local any=0
  if ls /sys/class/leds/*scroll* >/dev/null 2>&1; then
    for led in /sys/class/leds/*scroll*; do
      [ -w "$led/brightness" ] && echo 1 > "$led/brightness" 2>/dev/null || true
      any=1
    done
  fi
  for tty in /dev/tty[1-12]; do
    [ -r "$tty" ] && "$SETLEDS" -D +scroll < "$tty" 2>/dev/null || true
  done
  [ "$any" = 0 ] && log "no sysfs scroll leds; using setleds only"
}

burst(){
  apply_led; sleep 0.02
  apply_led; sleep 0.04
  apply_led; sleep 0.06
  apply_led; sleep 0.08
  apply_led
}

warmup(){
  local end=$(( $(date +%s) + 12 ))
  while [ "$(date +%s)" -lt "$end" ]; do
    burst
    sleep 0.12
  done
  log "warmup done"
}

aggressive_loop(){
  while true; do
    apply_led
    sleep 0.12
  done
}

watch_events_once(){
  if have udevadm && have awk && have stdbuf; then
    /usr/bin/udevadm monitor --kernel --udev --subsystem-match=leds --subsystem-match=input 2>/dev/null | stdbuf -oL awk '1' | while IFS= read -r _; do burst; done
    return 0
  else
    while true; do burst; sleep 0.08; done
  fi
}

watch_events_forever(){
  if have udevadm && have awk && have stdbuf; then
    while true; do
      log "starting udev monitor"
      watch_events_once || true
      log "udev monitor ended; restarting in 1s"
      sleep 1
    done
  else
    watch_events_once
  fi
}

case "${1-}" in
  --daemon)
    log "daemon start"
    warmup & aggressive_loop & watch_events_forever
    wait
    ;;
  --apply)
    apply_led
    ;;
  *)
    apply_led
    ;;
esac
SH
  sudo_wrap chmod +x /usr/local/bin/scrolllockd.sh

  sudo_wrap tee /etc/systemd/system/scrolllockd.service >/dev/null <<'UNIT'
[Unit]
Description=Scroll Lock backlight daemon (KeyLights - robust)
After=systemd-udevd.service local-fs.target getty.target
Wants=systemd-udevd.service

[Service]
Type=simple
ExecStartPre=/usr/bin/udevadm settle --timeout=10
ExecStartPre=/usr/local/bin/scrolllockd.sh --apply
ExecStart=/usr/local/bin/scrolllockd.sh --daemon
Restart=always
RestartSec=2
Nice=10

[Install]
WantedBy=multi-user.target
UNIT

  sudo_wrap systemctl daemon-reload
  sudo_wrap systemctl enable --now scrolllockd.service
  echo -e "${GREEN}KeyLights daemon installed and running.${NC}"
}

uninstall_all(){
  sudo_wrap systemctl disable --now scrolllockd.service 2>/dev/null || true
  sudo_wrap rm -f /etc/systemd/system/scrolllockd.service
  sudo_wrap systemctl daemon-reload
  sudo_wrap rm -f /usr/local/bin/scrolllockd.sh
  echo -e "${GREEN}KeyLights uninstalled.${NC}"
}

case "${1-}" in
  --uninstall) uninstall_all ;;
  *) install_core ;;
esac
