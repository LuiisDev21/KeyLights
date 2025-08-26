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
apply_led(){
  for tty in /dev/tty[1-12]; do
    [[ -r "$tty" ]] && /usr/bin/setleds -D +scroll < "$tty" || true
  done
  if ls /sys/class/leds/*scrolllock* >/dev/null 2>&1; then
    for led in /sys/class/leds/*scrolllock*; do
      [[ -w "$led/brightness" ]] && echo 1 > "$led/brightness" || true
    done
  fi
}
burst_reapply(){
  apply_led; sleep 0.05; apply_led; sleep 0.10; apply_led
}
event_watcher(){
  /usr/bin/udevadm monitor --kernel --udev --subsystem-match=leds --subsystem-match=input | \
  stdbuf -oL awk '1' | while IFS= read -r _; do burst_reapply; done
}
periodic_refresh(){ while true; do apply_led; sleep 30; done; }
fast_boot_warmup(){ end=$(( $(date +%s) + 8 )); while [ "$(date +%s)" -lt "$end" ]; do apply_led; sleep 0.2; done; }
ensure_tools(){ command -v setleds >/dev/null 2>&1 || exit 1; command -v udevadm >/dev/null 2>&1 || exit 1; command -v awk >/dev/null 2>&1 || exit 1; command -v stdbuf >/dev/null 2>&1 || exit 1; }
case "${1-}" in
  --daemon) ensure_tools; fast_boot_warmup &; periodic_refresh &; event_watcher ;;
  *) apply_led ;;
esac
SH
  sudo_wrap chmod +x /usr/local/bin/scrolllockd.sh

  sudo_wrap tee /etc/systemd/system/scrolllockd.service >/dev/null <<'UNIT'
[Unit]
Description=Scroll Lock backlight daemon (KeyLights)
After=local-fs.target

[Service]
Type=simple
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
