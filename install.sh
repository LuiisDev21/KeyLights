#!/usr/bin/env bash
set -euo pipefail

GREEN="\033[1;32m"; YELLOW="\033[1;33m"; RED="\033[1;31m"; NC="\033[0m"

want_x11=false
if [[ "${1-}" == "--x11" ]]; then
  want_x11=true
elif [[ "${1-}" == "--uninstall" ]]; then
  action="uninstall"
else
  action="install"
fi

need_cmd() { command -v "$1" >/dev/null 2>&1; }
sudo_wrap() {
  if [[ $EUID -ne 0 ]]; then sudo "$@"; else "$@"; fi
}

install_kbd() {
  if need_cmd setleds; then return; fi
  if need_cmd apt; then
    sudo_wrap apt update -y && sudo_wrap apt install -y kbd
  elif need_cmd dnf; then
    sudo_wrap dnf install -y kbd
  elif need_cmd pacman; then
    sudo_wrap pacman -Sy --noconfirm kbd
  elif need_cmd zypper; then
    sudo_wrap zypper install -y kbd
  else
    echo -e "${RED}Instala 'kbd' manualmente.${NC}"
  fi
}

install_core() {
  install_kbd
  sudo_wrap tee /usr/local/bin/scrolllock-backlight.sh >/dev/null <<'SH'
#!/usr/bin/env bash
set -euo pipefail
for tty in /dev/tty[1-12]; do
  if [ -r "$tty" ]; then
    /usr/bin/setleds -D +scroll < "$tty" || true
  fi
done
if ls /sys/class/leds/*scrolllock* >/dev/null 2>&1; then
  for led in /sys/class/leds/*scrolllock*; do
    if [ -w "$led/brightness" ]; then
      echo 1 > "$led/brightness" || true
    fi
  done
fi
SH
  sudo_wrap chmod +x /usr/local/bin/scrolllock-backlight.sh
  sudo_wrap tee /etc/systemd/system/scrolllock-backlight.service >/dev/null <<'UNIT'
[Unit]
Description=Enciende Scroll Lock para activar la luz del teclado al arrancar
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/scrolllock-backlight.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
  sudo_wrap systemctl daemon-reload
  sudo_wrap systemctl enable --now scrolllock-backlight.service
}

install_x11_user() {
  mkdir -p "$HOME/.config/systemd/user"
  cat > "$HOME/.config/systemd/user/scrolllock-x11.service" <<'UNIT'
[Unit]
Description=Reaplica Scroll Lock al iniciar sesión X11
After=graphical-session.target

[Service]
Type=oneshot
Environment=DISPLAY=:0
ExecStart=/usr/bin/xset led 3

[Install]
WantedBy=default.target
UNIT
  systemctl --user daemon-reload || true
  systemctl --user enable --now scrolllock-x11.service || true
}

uninstall_all() {
  if systemctl is-enabled --quiet scrolllock-backlight.service 2>/dev/null; then
    sudo_wrap systemctl disable --now scrolllock-backlight.service || true
  fi
  sudo_wrap rm -f /etc/systemd/system/scrolllock-backlight.service
  sudo_wrap rm -f /usr/local/bin/scrolllock-backlight.sh
  sudo_wrap systemctl daemon-reload
  systemctl --user disable --now scrolllock-x11.service 2>/dev/null || true
  rm -f "$HOME/.config/systemd/user/scrolllock-x11.service" 2>/dev/null || true
  systemctl --user daemon-reload 2>/dev/null || true
}

case "$action" in
  install)
    install_core
    $want_x11 && install_x11_user
    ;;
  uninstall)
    uninstall_all
    ;;
esac
