#!/bin/bash
set -euo pipefail

# =========================
# Arch Post Install Pro (Bash) - Full Auto with AUR Fail-Safe (Clean & Improved)
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
MISSING_SERVICES_FILE="$HOME/missing-services.log"
: > "$MISSING_PKGS_FILE"
: > "$MISSING_SERVICES_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

step() { echo -e "\n\033[1;36m[$(date +'%H:%M:%S')] ➤ $*\033[0m"; }
ok()   { echo -e "\033[1;32m✔ $*\033[0m"; }
warn() { echo -e "\033[1;33m⚠ $*\033[0m"; }
err()  { echo -e "\033[1;31m✖ $*\033[0m"; }

trap 'err "حصل خطأ! راجع اللوج: $LOG_FILE"' ERR

# ---- Helpers ----
with_timeout() {
  local seconds="$1"; shift
  if ! timeout "$seconds" "$@"; then
    return 124
  fi
}

enable_now_if_exists() {
  local unit="$1"
  if systemctl list-unit-files | awk '{print $1}' | grep -qx "$unit"; then
    if ! systemctl is-enabled --quiet "$unit"; then
      sudo systemctl enable --now "$unit"
      ok "تم تفعيل الخدمة: $unit"
    else
      ok "الخدمة مفعّلة بالفعل: $unit"
    fi
  else
    echo "$unit" >> "$MISSING_SERVICES_FILE"
  fi
}

enable_now_if_exists_fuzzy() {
  local unit="$1"
  local found
  # أولًا: دور على الخدمة بالاسم الكامل
  found=$(systemctl list-unit-files | awk '{print $1}' | grep -i "^$unit" | head -n1 || true)
  if [[ -z "$found" ]]; then
    # لو مش موجود بالاسم الكامل، دور على أي تطابق جزئي
    found=$(systemctl list-unit-files | awk '{print $1}' | grep -i "$unit" | head -n1 || true)
  fi

  if [[ -n "$found" ]]; then
    if ! systemctl is-enabled --quiet "$found"; then
      sudo systemctl enable --now "$found"
      ok "تم تفعيل الخدمة: $found"
    else
      ok "الخدمة مفعّلة بالفعل: $found"
    fi
  else
    echo "$unit" >> "$MISSING_SERVICES_FILE"
  fi
}

safe_rm_if_exists() {
  shopt -s nullglob
  local arr=( $1 )
  (( ${#arr[@]} )) && rm -rf "${arr[@]}"
  shopt -u nullglob
}

require_internet() {
  step "فحص الاتصال بالإنترنت"
  ping -c 1 -W 3 archlinux.org &>/dev/null && ok "الإنترنت شغال." || err "مفيش اتصال بالإنترنت."
}

require_sudo() {
  step "فحص صلاحيات sudo"
  sudo -n true &>/dev/null && ok "صلاحيات sudo جاهزة." || warn "السكربت هيطلب باسورد sudo عند الحاجة."
}

# ---- Pacman helpers ----
install_pacman_checked() {
  local pkgs=("$@")
  local avail=()
  for pkg in "${pkgs[@]}"; do
    pacman -Si "$pkg" &>/dev/null && avail+=("$pkg") || { warn "الحزمة مش موجودة في مستودعات pacman: $pkg"; echo "$pkg" >> "$MISSING_PKGS_FILE"; }
  done
  (( ${#avail[@]} )) && sudo pacman -S --noconfirm --needed -q "${avail[@]}" || warn "مفيش حزم صالحة للتثبيت من pacman."
}

# ---- AUR helpers ----
ensure_yay() {
  command -v yay &>/dev/null && { ok "yay موجود بالفعل"; return 0; }
  step "تثبيت yay (AUR)"
  sudo pacman -S --needed --noconfirm base-devel git || true
  tmpdir=$(mktemp -d)
  if with_timeout "$YAY_MAKE_TIMEOUT" git clone https://aur.archlinux.org/yay-bin.git "$tmpdir/yay-bin"; then
    pushd "$tmpdir/yay-bin" >/dev/null
    with_timeout "$YAY_MAKE_TIMEOUT" makepkg -si --noconfirm && ok "تم تثبيت yay" || warn "فشل makepkg لتثبيت yay."
    popd >/dev/null || true
  else
    warn "فشل git clone من AUR."
  fi
  rm -rf "$tmpdir"
}

install_aur_failsafe() {
  command -v yay &>/dev/null || { warn "yay مش متاح؛ تخطى كل حزم AUR: ${*}"; for p in "$@"; do echo "$p" >> "$MISSING_PKGS_FILE"; done; return; }
  for pkg in "$@"; do
    step "تثبيت من AUR: $pkg"
    with_timeout "$AUR_TIMEOUT" yay -S --needed --noconfirm --removemake --answerdiff None --answeredit None --noredownload "$pkg" && ok "تم تثبيت $pkg (AUR)" || { warn "فشل تثبيت $pkg من AUR."; echo "$pkg" >> "$MISSING_PKGS_FILE"; }
  done
}

# ========================= تنفيذ =========================
require_internet
require_sudo

# 0) pacman.conf
step "تصحيح إعدادات pacman.conf"
sudo sed -i '/ILoveCandy/d' /etc/pacman.conf
grep -q '^ILoveCandy' /etc/pacman.conf || sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
ok "تم تصحيح pacman.conf"

# 1) تحديث النظام + Flathub
step "تحديث النظام وإضافة Flathub"
install_pacman_checked flatpak
sudo pacman -Syu --noconfirm || true
with_timeout "$FLATPAK_TIMEOUT" flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || warn "تخطى إضافة Flathub."
with_timeout "$FLATPAK_TIMEOUT" flatpak update --appstream -y || true
ok "تم."

# 1.1) برامج Flatpak
step "تثبيت برامج Flatpak"
with_timeout "$FLATPAK_TIMEOUT" flatpak install -y flathub \
  com.github.iwalton3.jellyfin-mpv-shim \
  com.github.tchx84.Flatseal || warn "تخطى بعض تطبيقات Flatpak."
ok "تم تثبيت برامج Flatpak."

# 2) reflector
step "تثبيت reflector وتحديث المرايا"
install_pacman_checked reflector
with_timeout "$REFLECTOR_TIMEOUT" sudo reflector --country "Egypt,Germany,Netherlands" --protocol https --latest 20 --sort rate --score 10 --save /etc/pacman.d/mirrorlist || warn "reflector فشل."
sudo pacman -Syy || true
ok "تم تحديث /etc/pacman.d/mirrorlist"

# 3) الحزم الأساسية
step "تثبيت الحزم الأساسية (pacman)"
install_pacman_checked \
  archlinux-keyring git base-devel pacman-contrib reflector \
  noto-fonts noto-fonts-emoji noto-fonts-extra \
  ttf-dejavu ttf-liberation ttf-scheherazade-new \
  mpv mkvtoolnix-gui firefox qbittorrent \
  power-profiles-daemon ufw gamemode lib32-gamemode \
  xdg-user-dirs networkmanager ntp thermald
ok "تم تثبيت الحزم."

# 4) تحسين pacman
step "تحسين pacman"
sudo sed -i 's/^#Color/Color/' /etc/pacman.conf || true
grep -q '^#ParallelDownloads' /etc/pacman.conf && sudo sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf || (grep -q '^ParallelDownloads' /etc/pacman.conf || echo "ParallelDownloads = 5" | sudo tee -a /etc/pacman.conf >/dev/null)
ok "تم."

# 5) الخدمات الأساسية
step "تفعيل الخدمات الأساسية"
SERVICES=(ufw.service power-profiles-daemon.service NetworkManager.service apparmor.service fstrim.timer thermald.service paccache.timer)
for svc in "${SERVICES[@]}"; do enable_now_if_exists_fuzzy "$svc"; done
sudo ufw enable || true
sudo timedatectl set-ntp true || true
id -nG "$USER" | grep -qw gamemode || { sudo usermod -aG gamemode "$USER"; ok "تم إضافة $USER لمجموعة gamemode."; }
xdg-user-dirs-update || true

# 6) zram
step "تهيئة zram"
install_pacman_checked zram-generator
ZCONF="/etc/systemd/zram-generator.conf"
[[ -f "$ZCONF" ]] || { sudo tee "$ZCONF" >/dev/null <<< $'[zram0]\nzram-size = ram / 2\ncompression-algorithm = zstd'; sudo systemctl daemon-reload; warn "zram هيتفعل بعد إعادة التشغيل."; }
ok "ملف zram-generator.conf موجود بالفعل أو تم إنشاؤه."

# 7) sysctl
step "ضبط sysctl"
SYSCTL="/etc/sysctl.d/99-tuned.conf"
sudo tee "$SYSCTL" >/dev/null <<'EOF'
vm.swappiness = 10
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
vm.vfs_cache_pressure = 75
EOF
sudo sysctl --system >/dev/null 2>&1 || true
ok "تم تطبيق إعدادات sysctl"

# 8) yay
ensure_yay

# 9) AUR
step "تثبيت حزم من AUR"
install_aur_failsafe ttf-amiri ttf-sil-harmattan ffmpegthumbs-git autosubsync-bin
ok "انتهى قسم AUR."

# 10) مؤقّت التحديثات
step "إعداد مؤقّت لفحص التحديثات"
sudo tee /etc/systemd/system/arch-checkupdates.service >/dev/null <<'EOF'
[Unit]
Description=Arch checkupdates logger
[Service]
Type=oneshot
ExecStart=/bin/bash -c '/usr/bin/checkupdates || true'
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
enable_now_if_exists_fuzzy arch-checkupdates.timer
ok "تم."

# 11) تنظيف
step "تنظيف النظام"
sudo paccache -r || true
sudo pacman -Rns --noconfirm $(pacman -Qtdq || true) || true
yay -Sc --noconfirm || true
sudo journalctl --vacuum-time=7d || true
with_timeout "$FLATPAK_TIMEOUT" flatpak uninstall --unused -y || true
sudo pacman -Sc --noconfirm || true

safe_rm_if_exists "$HOME/.cache/"*
safe_rm_if_exists "$HOME/.npm/"*
safe_rm_if_exists "$HOME/.cargo/registry"*
safe_rm_if_exists "$HOME/.cargo/git"*

ok "تم التنظيف."

# Summary
END_TIME=$(date +'%F %T')
echo
ok "✨ خلصنا! بدأ: $START_TIME — انتهى: $END_TIME"
echo "📄 ملف اللوج: $LOG_FILE"
[[ -s "$MISSING_PKGS_FILE" ]] && warn "📦 حزم مفقودة: $MISSING_PKGS_FILE"
[[ -s "$MISSING_SERVICES_FILE" ]] && warn "🧩 خدمات مفقودة: $MISSING_SERVICES_FILE"
echo "💡 ملاحظات:"
echo "- يفضل إعادة التشغيل علشان zram يشتغل."
echo "- gamemode يتفعل بعد تسجيل الخروج/الدخول."
echo "- سجل التحديثات اليومية: /var/log/arch-updates.log"
