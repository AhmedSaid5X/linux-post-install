#!/bin/bash
set -euo pipefail

# =========================
# Arch Post Install - Clean & Auto (Non-Interactive, AUR-safe)
# =========================

# ---- Config ----
AUR_TIMEOUT=${AUR_TIMEOUT:-180}
PARU_MAKE_TIMEOUT=${PARU_MAKE_TIMEOUT:-300}
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

require_internet() {
  step "فحص الاتصال بالإنترنت"
  ping -c1 -W3 archlinux.org &>/dev/null && ok "الإنترنت شغال." || err "مفيش اتصال بالإنترنت."
}

remove_pacman_lock() {
  if [[ -f /var/lib/pacman/db.lck ]]; then
    warn "تم العثور على قفل pacman موجود، جاري إزالته..."
    sudo rm -f /var/lib/pacman/db.lck && ok "تم إزالة قفل pacman."
  fi
}

# ---- Pacman ----
install_pacman_checked() {
  remove_pacman_lock
  local pkgs=("$@")
  local avail=()
  for pkg in "${pkgs[@]}"; do
    pacman -Si "$pkg" &>/dev/null && avail+=("$pkg") || { warn "$pkg مش موجود في pacman"; echo "$pkg" >> "$MISSING_PKGS_FILE"; }
  done
  (( ${#avail[@]} )) && sudo pacman -S --noconfirm --needed -q "${avail[@]}"
}

# ---- Paru (AUR helper) ----
ensure_paru() {
  command -v paru &>/dev/null && { ok "paru موجود"; return; }
  step "تثبيت paru"
  install_pacman_checked base-devel git
  tmpdir=$(mktemp -d)
  git clone https://aur.archlinux.org/paru-bin.git "$tmpdir/paru-bin"
  pushd "$tmpdir/paru-bin" >/dev/null
  makepkg -si --noconfirm || warn "فشل makepkg لتثبيت paru"
  popd >/dev/null
  rm -rf "$tmpdir"
}

install_aur_failsafe() {
  command -v paru &>/dev/null || { warn "paru مش موجود؛ تخطى كل حزم AUR"; return; }

  for pkg in "$@"; do
    step "تثبيت AUR: $pkg"

    if paru -Qi "$pkg" &>/dev/null; then
      ok "$pkg مثبت بالفعل"
      continue
    fi

    paru -S --needed --noconfirm "$pkg"

    if [[ $? -ne 0 ]]; then
      warn "فشل تثبيت $pkg"
      echo "$pkg" >> "$MISSING_PKGS_FILE"
    fi
  done
}

# ========================= تنفيذ =========================
require_internet

# ---- تفعيل multilib repo ----
step "تفعيل [multilib] repo"
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
  sudo sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
  ok "[multilib] اتفعل"
else
  ok "[multilib] متفعل بالفعل"
fi
sudo pacman -Sy --noconfirm || warn "⚠ تحديث pacman بعد تفعيل multilib فشل"

# ---- pacman.conf ----
step "تصحيح إعدادات pacman.conf"
sudo sed -i '/ILoveCandy/d' /etc/pacman.conf
sudo sed -i '/^#*Color/d' /etc/pacman.conf
sudo sed -i '/\[options\]/a Color\nILoveCandy' /etc/pacman.conf
ok "تم تفعيل Color و ILoveCandy"

# ---- تحديث قاعدة بيانات pacman ----
step "تحديث قاعدة بيانات الحزم"
sudo pacman -Sy --noconfirm || warn "⚠ تحديث قاعدة بيانات pacman فشل، استمر على مسؤوليتك"

# ---- تحديث النظام & Flatpak ----
step "تحديث النظام وإضافة Flathub"
install_pacman_checked flatpak reflector
sudo pacman -Syu --noconfirm || true
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
flatpak update --appstream -y || true

# ---- برامج Flatpak ----
step "تثبيت برامج Flatpak"
flatpak install -y flathub com.github.iwalton3.jellyfin-mpv-shim || true
flatpak install -y flathub org.nickvision.tubeconverter || true

# ---- تحديث المرايا ----
step "تحديث mirrorlist"
with_timeout "$REFLECTOR_TIMEOUT" sudo reflector \
  --country "Egypt,Germany,Netherlands" \
  --protocol https \
  --latest 20 \
  --sort rate \
  --score 10 \
  --fastest 20 \
  --save /etc/pacman.d/mirrorlist || warn "⚠ بعض المرايا فشلت، تم استخدام المرايا المتاحة."
sudo pacman -Syy || true
ok "تم تحديث mirrorlist"

# ---- الحزم الأساسية ----
step "تثبيت الحزم الأساسية"
install_pacman_checked \
  archlinux-keyring git base-devel pacman-contrib \
  noto-fonts noto-fonts-emoji timeshift \
  ttf-dejavu ttf-liberation \
  mpv mkvtoolnix-gui fastfetch qbittorrent \
  power-profiles-daemon ufw unrar zip \
  xdg-user-dirs networkmanager ntp gwenview \
  btrfs-progs xfsprogs f2fs-tools exfatprogs ntfs-3g \
  dosfstools mtools udftools unzip discord \
  nfs-utils cifs-utils sshfs partitionmanager \
  pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber \
  bluez bluez-utils cups cups-pdf system-config-printer \
  hyphen-en lib32-openssl wget curl htop \
  man-db man-pages texinfo grc bat lutris gamescope lib32-mangohud gamemode lib32-gamemode goverlay \
  ripgrep fd tree jq yq ncdu pv aria2
ok "تم"

# ---- CPU Microcode ----
step "تثبيت microcode المناسب للمعالج"
if grep -q "AuthenticAMD" /proc/cpuinfo; then
  install_pacman_checked amd-ucode
  ok "AMD microcode اتثبت"
elif grep -q "GenuineIntel" /proc/cpuinfo; then
  install_pacman_checked intel-ucode
  ok "Intel microcode اتثبت"
else
  warn "معالج غير معروف، microcode متثبتش"
fi

# ---- الخدمات الأساسية ----
step "تفعيل الخدمات"
SERVICES=(ufw.service power-profiles-daemon.service NetworkManager.service fstrim.timer paccache.timer bluetooth.service cups.service)
for svc in "${SERVICES[@]}"; do enable_service "$svc"; done
sudo ufw enable || true
sudo timedatectl set-ntp true || true

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

# ---- تثبيت حزم من AUR ----
ensure_paru
step "تثبيت حزم من AUR (تلقائي)"
install_aur_failsafe \
  ffmpegthumbs-git proton-ge-custom-bin zen-browser-bin \
  autosubsync-bin renamemytvseries-qt-bin jellyfin-media-player \
  subtitlecomposer visual-studio-code-bin bauh spotify flatseal

# ---- SpotX ----
step "تعديل Spotify ب SpotX"
bash <(curl -sSL https://spotx-official.github.io/run.sh) || warn "فشل تشغيل SpotX"
ok "Spotify اتظبط ب SpotX"

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

# ---- تنظيف (Ultimate Cleanup) ----
step "تشغيل سكربت التنظيف Ultimate Cleanup"
PACMAN_CACHE_DAYS=30
JOURNAL_DAYS=7
TMP_DAYS=7
LOG_SIZE_LIMIT=100M
echo "🧹 بدء تنظيف النظام Ultimate Non-Interactive على Arch Linux..."

# تحديث النظام
echo "⬆ تحديث النظام..."
sudo pacman -Syu --noconfirm

# تنظيف pacman cache
echo "🗑 تنظيف pacman cache..."
sudo find /var/cache/pacman/pkg/ -type d -name "download-*" -exec rm -rf {} + 2>/dev/null
sudo find /var/cache/pacman/pkg/ -type f -exec rm -f {} + 2>/dev/null
sudo paccache -r -k "${PACMAN_CACHE_DAYS}" || true

# إزالة orphan
ORPHANS=$(pacman -Qdtq || true)
if [ -n "$ORPHANS" ]; then
    echo "🗑 إزالة الحزم orphan..."
    sudo pacman -Rns --noconfirm $ORPHANS
fi

# تنظيف paru
if command -v paru &>/dev/null; then
    echo "🗑 تنظيف Paru cache بالكامل..."
    rm -rf ~/.cache/paru/* ~/.cache/paru/clone ~/.cache/paru/diff || true
    paru -Sc --noconfirm || true
fi

# تنظيف flatpak
if command -v flatpak &>/dev/null; then
    echo "🗑 تنظيف flatpak..."
    flatpak uninstall --unused --assumeyes || true
    flatpak repair || true
fi

# journal
echo "📜 تنظيف journal..."
sudo journalctl --vacuum-time="${JOURNAL_DAYS}d" || true

# tmp
echo "🧹 تنظيف /tmp و /var/tmp..."
sudo find /tmp -type f -mtime +${TMP_DAYS} -delete || true
sudo find /var/tmp -type f -mtime +${TMP_DAYS} -delete || true

# logs
echo "📂 حذف ملفات log الكبيرة (> ${LOG_SIZE_LIMIT})..."
sudo find /var/log -type f -size +${LOG_SIZE_LIMIT} -exec rm -f {} + 2>/dev/null || true

echo "✅ انتهى تنظيف النظام Ultimate Non-Interactive! كل حاجة جاهزة."

# ---- نهاية ----
END_TIME=$(date +'%F %T')
ok "✨ خلصنا! بدأ: $START_TIME — انتهى: $END_TIME"
[[ -s "$MISSING_PKGS_FILE" ]] && warn "📦 حزم مفقودة: $MISSING_PKGS_FILE"
echo "💡 يفضل إعادة التشغيل علشان zram و microcode يشتغلوا."
