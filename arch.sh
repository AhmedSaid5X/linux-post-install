#!/bin/bash
set -euo pipefail

# =========================
# Arch Post Install - Clean & Auto
# =========================

# ---- Config ----
AUR_TIMEOUT=${AUR_TIMEOUT:-180}
YAY_MAKE_TIMEOUT=${YAY_MAKE_TIMEOUT:-300}
FLATPAK_TIMEOUT=${FLATPAK_TIMEOUT:-180}
REFLECTOR_TIMEOUT=${REFLECTOR_TIMEOUT:-60}

# ---- Logging & UI ----
START_TIME=$(date +'%F %T')
LOG_FILE="$HOME/arch-post-install-$(date +'%Y%m%d-%H%M%S').log"
MISSING_PKGS_FILE="$HOME/missing-packages.log"
: > "$MISSING_PKGS_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

step() { echo -e "\n\033[1;36m[$(date +'%H:%M:%S')] ➤ $*\033[0m"; }
ok()   { echo -e "\033[1;32m✔ $*\033[0m"; }
warn() { echo -e "\033[1;33m⚠ $*\033[0m"; }
err()  { echo -e "\033[1;31m✖ $*\033[0m"; }

trap 'err "حصل خطأ! راجع اللوج: $LOG_FILE"' ERR

# ---- Helpers ----
with_timeout() {
  local seconds="$1"; shift
  timeout "$seconds" "$@" || return 124
}

enable_service() {
  local svc="$1"
  local found=$(systemctl list-unit-files | awk '{print $1}' | grep -i "^$svc" | head -n1 || true)
  [[ -z "$found" ]] && found=$(systemctl list-unit-files | awk '{print $1}' | grep -i "$svc" | head -n1 || true)
  if [[ -n "$found" ]]; then
    sudo systemctl enable --now "$found" || true
    ok "الخدمة مفعّلة: $found"
  else
    echo "$svc" >> "$MISSING_PKGS_FILE"
  fi
}

safe_rm_if_exists() {
  shopt -s nullglob
  local arr=( "$1" )
  (( ${#arr[@]} )) && rm -rf "${arr[@]}"
  shopt -u nullglob
}

require_internet() {
  step "فحص الاتصال بالإنترنت"
  ping -c1 -W3 archlinux.org &>/dev/null && ok "الإنترنت شغال." || err "مفيش اتصال بالإنترنت."
}

require_sudo() {
  step "فحص صلاحيات sudo"
  sudo -n true &>/dev/null && ok "صلاحيات sudo جاهزة." || warn "السكربت هيطلب باسورد sudo عند الحاجة."
}

# ---- Pacman & AUR ----
install_pacman_checked() {
  local pkgs=("$@")
  local avail=()
  for pkg in "${pkgs[@]}"; do
    pacman -Si "$pkg" &>/dev/null && avail+=("$pkg") || { warn "$pkg مش موجود في pacman"; echo "$pkg" >> "$MISSING_PKGS_FILE"; }
  done
  (( ${#avail[@]} )) && sudo pacman -S --noconfirm --needed -q "${avail[@]}"
}

ensure_yay() {
  command -v yay &>/dev/null && { ok "yay موجود"; return; }
  step "تثبيت yay"
  sudo pacman -S --needed --noconfirm base-devel git || true
  tmpdir=$(mktemp -d)
  git clone https://aur.archlinux.org/yay-bin.git "$tmpdir/yay-bin"
  pushd "$tmpdir/yay-bin" >/dev/null
  makepkg -si --noconfirm || warn "فشل makepkg لتثبيت yay"
  popd >/dev/null
  rm -rf "$tmpdir"
}

install_aur_failsafe() {
  command -v yay &>/dev/null || { warn "yay مش موجود؛ تخطى كل حزم AUR"; return; }
  for pkg in "$@"; do
    step "تثبيت AUR: $pkg"
    yay -S --needed --noconfirm "$pkg" || { warn "فشل تثبيت $pkg"; echo "$pkg" >> "$MISSING_PKGS_FILE"; }
  done
}

# ========================= تنفيذ =========================
require_internet
require_sudo

# ---- pacman.conf ----
step "تصحيح إعدادات pacman.conf"
sudo sed -i '/ILoveCandy/d' /etc/pacman.conf
grep -q '^ILoveCandy' /etc/pacman.conf || sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
ok "تم"

# ---- تحديث النظام & Flatpak ----
step "تحديث النظام وإضافة Flathub"
install_pacman_checked flatpak reflector
sudo pacman -Syu --noconfirm || true
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
flatpak update --appstream -y || true

# ---- برامج Flatpak ----
step "تثبيت برامج Flatpak"
flatpak install -y flathub com.github.iwalton3.jellyfin-mpv-shim com.github.tchx84.Flatseal || true

# ---- تحديث المرايا ----
step "تحديث mirrorlist"
with_timeout "$REFLECTOR_TIMEOUT" sudo reflector --country "Egypt,Germany,Netherlands" --protocol https --latest 20 --sort rate --score 10 --save /etc/pacman.d/mirrorlist || warn "فشل reflector"
sudo pacman -Syy || true

# ---- الحزم الأساسية ----
step "تثبيت الحزم الأساسية"
install_pacman_checked \
  archlinux-keyring git base-devel pacman-contrib \
  noto-fonts noto-fonts-emoji noto-fonts-extra \
  ttf-dejavu ttf-liberation ttf-scheherazade-new \
  mpv mkvtoolnix-gui firefox qbittorrent \
  power-profiles-daemon ufw gamemode lib32-gamemode \
  xdg-user-dirs networkmanager ntp thermald unrar
ok "تم"

# ---- الخدمات الأساسية ----
step "تفعيل الخدمات"
SERVICES=(ufw.service power-profiles-daemon.service NetworkManager.service fstrim.timer thermald.service paccache.timer)
for svc in "${SERVICES[@]}"; do enable_service "$svc"; done
sudo ufw enable || true
sudo timedatectl set-ntp true || true
id -nG "$USER" | grep -qw gamemode || sudo usermod -aG gamemode "$USER"

# ---- zram ----
step "تهيئة zram"
install_pacman_checked zram-generator
ZCONF="/etc/systemd/zram-generator.conf"
[[ -f "$ZCONF" ]] || { sudo tee "$ZCONF" >/dev/null <<< $'[zram0]\nzram-size = ram / 2\ncompression-algorithm = zstd'; sudo systemctl daemon-reload; warn "zram هيتفعل بعد إعادة التشغيل."; }

# ---- sysctl ----
step "ضبط sysctl"
sudo tee /etc/sysctl.d/99-tuned.conf >/dev/null <<'EOF'
vm.swappiness = 10
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
vm.vfs_cache_pressure = 75
EOF
sudo sysctl --system >/dev/null 2>&1 || true
ok "تم"

# ---- AUR ----
ensure_yay
step "تثبيت حزم من AUR"
install_aur_failsafe ttf-amiri ttf-sil-harmattan ffmpegthumbs-git autosubsync-bin renamemytvseries-qt-bin jellyfin-media-player \
subtitlecomposer

# ---- checkupdates timer ----
step "إعداد تحديثات يومية"
sudo tee /etc/systemd/system/arch-checkupdates.service >/dev/null <<'EOF'
[Unit]
Description=Arch checkupdates logger
[Service]
Type=oneshot
ExecStart=/usr/bin/checkupdates || true
StandardOutput=append:/var/log/arch-updates.log
StandardError=append:/var/log/arch-updates.log
EOF
sudo tee /etc/systemd/system/arch-checkupdates.timer >/dev/null <<'EOF'
[Unit]
Description=Run arch-checkupdates daily
[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=900
[Install]
WantedBy=timers.target
EOF
sudo systemctl daemon-reload
enable_service arch-checkupdates.timer

# ---- تنظيف ----
step "تنظيف النظام"
sudo paccache -r || true
sudo pacman -Rns --noconfirm $(pacman -Qtdq || true) || true
yay -Sc --noconfirm || true
sudo journalctl --vacuum-time=7d || true
flatpak uninstall --unused -y || true

safe_rm_if_exists "$HOME/.cache/"*

# ---- نهاية ----
END_TIME=$(date +'%F %T')
ok "✨ خلصنا! بدأ: $START_TIME — انتهى: $END_TIME"
[[ -s "$MISSING_PKGS_FILE" ]] && warn "📦 حزم مفقودة: $MISSING_PKGS_FILE"
echo "💡 يفضل إعادة التشغيل علشان zram يشتغل و gamemode يتفعل بعد تسجيل الخروج/الدخول."
