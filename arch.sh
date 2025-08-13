#!/bin/bash
set -euo pipefail

# =========================
# Arch Post Install Pro (Bash) - Full Mode (with pre-check & missing logs)
# =========================

# ---- Logging & UI ----
START_TIME=$(date +'%F %T')
LOG_FILE="$HOME/arch-post-install-$(date +'%Y%m%d-%H%M%S').log"
MISSING_PKGS_FILE="$HOME/missing-packages.log"
MISSING_SERVICES_FILE="$HOME/missing-services.log"

# صافى ملفات المفقود كل مرّة تشغيل
: > "$MISSING_PKGS_FILE"
: > "$MISSING_SERVICES_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1

step() { echo -e "\n\033[1;36m[$(date +'%H:%M:%S')] ➤ $*\033[0m"; }
ok()   { echo -e "\033[1;32m✔ $*\033[0m"; }
warn() { echo -e "\033[1;33m⚠ $*\033[0m"; }
err()  { echo -e "\033[1;31m✖ $*\033[0m"; }

trap 'err "حصل خطأ! راجع اللوج: $LOG_FILE"' ERR

# ---- Helpers ----
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
    warn "الخدمة مش موجودة: $unit"
    echo "$unit" >> "$MISSING_SERVICES_FILE"
  fi
}

safe_rm_if_exists() {
  shopt -s nullglob
  local arr=( $1 )
  if (( ${#arr[@]} )); then
    rm -rf "${arr[@]}"
  fi
  shopt -u nullglob
}

require_internet() {
  step "فحص الاتصال بالإنترنت"
  if ping -c 1 -W 3 archlinux.org &>/dev/null; then
    ok "الإنترنت شغال."
  else
    err "مفيش اتصال بالإنترنت."
  fi
}

require_sudo() {
  step "فحص صلاحيات sudo"
  if sudo -n true 2>/dev/null; then
    ok "صلاحيات sudo جاهزة."
  else
    warn "السكربت هيطلب باسورد sudo عند الحاجة."
  fi
}

# ---- Package checkers (pacman + AUR) ----
filter_available_packages_pacman() {
  local pkgs=("$@")
  local found=()
  for pkg in "${pkgs[@]}"; do
    if pacman -Si "$pkg" &>/dev/null; then
      found+=("$pkg")
    else
      warn "الحزمة مش موجودة في مستودعات pacman: $pkg"
      echo "$pkg" >> "$MISSING_PKGS_FILE"
    fi
  done
  printf '%s\n' "${found[@]}"
}

filter_available_packages_aur() {
  local pkgs=("$@")
  local found=()
  for pkg in "${pkgs[@]}"; do
    if yay -Si "$pkg" &>/dev/null; then
      found+=("$pkg")
    else
      warn "الحزمة مش موجودة في AUR: $pkg"
      echo "$pkg" >> "$MISSING_PKGS_FILE"
    fi
  done
  printf '%s\n' "${found[@]}"
}

install_pacman_checked() {
  mapfile -t _avail < <(filter_available_packages_pacman "$@")
  if (( ${#_avail[@]} )); then
    sudo pacman -S --noconfirm --needed -q "${_avail[@]}"
  else
    warn "مفيش ولا حزمة صالحة للتثبيت من pacman فى البلوك ده."
  fi
}

install_aur_checked() {
  mapfile -t _avail < <(filter_available_packages_aur "$@")
  if (( ${#_avail[@]} )); then
    yay -S --needed --noconfirm "${_avail[@]}"
  else
    warn "مفيش ولا حزمة صالحة للتثبيت من AUR فى البلوك ده."
  fi
}

# ---- 1) تحديث النظام + Flathub ----
require_internet
require_sudo

step "تحديث النظام وإضافة Flathub"
install_pacman_checked flatpak
sudo pacman -Syu --noconfirm
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak update --appstream -y
ok "تم."

# ---- 1.1) تثبيت برامج Flatpak ----
step "تثبيت برامج Flatpak"
flatpak install -y flathub \
  com.github.iwalton3.jellyfin-mpv-shim \
  com.github.tchx84.Flatseal || true
ok "تم تثبيت برامج Flatpak."

# ---- 2) اختيار أسرع مرايا ----
step "تثبيت reflector وتحديث قائمة المرايا"
install_pacman_checked reflector
sudo reflector --country "Egypt","Germany","Netherlands" --protocol https \
  --latest 20 --sort rate --score 10 --save /etc/pacman.d/mirrorlist || warn "reflector فشل فى كتابة mirrorlist (تأكد من الصلاحيات/الشبكة)"
sudo pacman -Syy
ok "تم تحديث /etc/pacman.d/mirrorlist"

# ---- 3) الحزم الأساسية ----
step "تثبيت الحزم الأساسية (pacman)"
install_pacman_checked \
  archlinux-keyring \
  git base-devel pacman-contrib reflector \
  noto-fonts noto-fonts-emoji noto-fonts-extra \
  ttf-dejavu ttf-liberation ttf-scheherazade-new \
  mpv mkvtoolnix-gui firefox qbittorrent \
  power-profiles-daemon ufw gamemode lib32-gamemode \
  xdg-user-dirs networkmanager ntp apparmor \
  thermald fail2ban
ok "تم تثبيت الحزم."

# ---- 4) تحسين إعدادات pacman ----
step "تحسين pacman"
sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
if grep -q '^#ParallelDownloads' /etc/pacman.conf; then
  sudo sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
elif ! grep -q '^ParallelDownloads' /etc/pacman.conf; then
  echo "ParallelDownloads = 5" | sudo tee -a /etc/pacman.conf >/dev/null
fi
grep -q '^ILoveCandy' /etc/pacman.conf || echo "ILoveCandy" | sudo tee -a /etc/pacman.conf >/dev/null
ok "تم."

# ---- 5) تفعيل الخدمات الأساسية ----
step "تفعيل الخدمات الأساسية"
sudo ufw enable || true
enable_now_if_exists ufw.service || enable_now_if_exists ufw
enable_now_if_exists power-profiles-daemon.service
enable_now_if_exists NetworkManager.service
enable_now_if_exists apparmor.service
enable_now_if_exists fstrim.timer
sudo timedatectl set-ntp true
enable_now_if_exists thermald.service
enable_now_if_exists systemd-oomd.service
enable_now_if_exists fail2ban.service
enable_now_if_exists paccache.timer
ok "تم ضبط الخدمات."

if ! id -nG "$USER" | grep -qw gamemode; then
  sudo usermod -aG gamemode "$USER"
  ok "تم إضافة $USER لمجموعة gamemode (سجّل خروج/دخول)."
else
  ok "مجموعة gamemode مضافة بالفعل."
fi

xdg-user-dirs-update || true

# ---- 6) إعداد zram ----
step "تهيئة zram"
install_pacman_checked zram-generator
ZCONF="/etc/systemd/zram-generator.conf"
if [[ ! -f "$ZCONF" ]]; then
  sudo tee "$ZCONF" >/dev/null <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF
  sudo systemctl daemon-reload
  warn "zram هيتفعل بعد إعادة التشغيل."
else
  ok "ملف zram-generator.conf موجود بالفعل"
fi

# ---- 7) تحسينات sysctl ----
step "ضبط sysctl"
SYSCTL="/etc/sysctl.d/99-tuned.conf"
sudo tee "$SYSCTL" >/dev/null <<'EOF'
vm.swappiness = 10
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
vm.vfs_cache_pressure = 75
EOF
sudo sysctl --system >/div/null 2>&1 || sudo sysctl --system >/dev/null
ok "تم تطبيق إعدادات sysctl"

# ---- 8) تثبيت yay ----
step "تثبيت yay (AUR)"
if ! command -v yay &>/dev/null; then
  tmpdir=$(mktemp -d)
  git clone https://aur.archlinux.org/yay-bin.git "$tmpdir"
  pushd "$tmpdir" >/dev/null
  makepkg -si --noconfirm
  popd >/dev/null
  rm -rf "$tmpdir"
  yay -Y --gendb
  yay -Syu --devel --noconfirm
  ok "تم تثبيت yay"
else
  ok "yay موجود بالفعل"
fi

# ---- 9) تثبيت حزم AUR ----
step "تثبيت حزم من AUR"
install_aur_checked \
  ttf-amiri ttf-sil-harmattan ffmpegthumbs-git autosubsync-bin
ok "تم."

# ---- 10) مؤقّت checkupdates ----
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
enable_now_if_exists arch-checkupdates.timer
ok "تم."

# ---- 11) تنظيفات ----
step "تنظيف النظام"
sudo paccache -r || true
sudo pacman -Rns --noconfirm $(pacman -Qtdq || true) || true
yay -Sc --noconfirm || true
sudo journalctl --vacuum-time=7d || true
flatpak uninstall --unused -y || true
sudo pacman -Sc --noconfirm || true

safe_rm_if_exists "$HOME/.cache/"*
safe_rm_if_exists "$HOME/.npm/"*
safe_rm_if_exists "$HOME/.cargo/registry"*
safe_rm_if_exists "$HOME/.cargo/git"*

ok "تم التنظيف."

# ---- Summary ----
END_TIME=$(date +'%F %T')
echo
ok "✨ خلصنا! بدأ: $START_TIME — انتهى: $END_TIME"
echo "📄 ملف اللوج: $LOG_FILE"
[[ -s "$MISSING_PKGS_FILE" ]] && warn "📦 حزم مفقودة (راجع وعدّل الاسكربت): $MISSING_PKGS_FILE"
[[ -s "$MISSING_SERVICES_FILE" ]] && warn "🧩 خدمات مفقودة (راجع وعدّل الاسكربت): $MISSING_SERVICES_FILE"
echo "💡 ملاحظات:"
echo "- يفضل إعادة التشغيل علشان zram يشتغل."
echo "- gamemode يتفعل بعد تسجيل الخروج/الدخول."
echo "- سجل التحديثات اليومية: /var/log/arch-updates.log"
