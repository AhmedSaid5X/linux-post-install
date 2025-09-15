#!/bin/bash
set -euo pipefail

# =========================
# Arch Post Install - Essential vs Optional (Full Script with Classification)
# =========================

# ---- Config ----
AUR_TIMEOUT=${AUR_TIMEOUT:-180}
PARU_MAKE_TIMEOUT=${PARU_MAKE_TIMEOUT:-300}
FLATPAK_TIMEOUT=${FLATPAK_TIMEOUT:-180}

# ---- Logging ----
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
  [[ -f /var/lib/pacman/db.lck ]] && sudo rm -f /var/lib/pacman/db.lck && warn "تم إزالة قفل pacman"
}

install_pacman_checked() {
  remove_pacman_lock
  local pkgs=("$@")
  local avail=()
  for pkg in "${pkgs[@]}"; do
    pacman -Si "$pkg" &>/dev/null && avail+=("$pkg") || { warn "$pkg مش موجود في pacman"; echo "$pkg" >> "$MISSING_PKGS_FILE"; }
  done
  (( ${#avail[@]} )) && sudo pacman -S --noconfirm --needed -q "${avail[@]}"
}

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
    if paru -Qi "$pkg" &>/dev/null; then ok "$pkg مثبت بالفعل"; continue; fi
    paru -S --needed --noconfirm "$pkg" || { warn "فشل تثبيت $pkg"; echo "$pkg" >> "$MISSING_PKGS_FILE"; }
  done
}

# ========================= تنفيذ =========================
require_internet

# ---- pacman.conf ----
step "تصحيح إعدادات pacman.conf"
sudo sed -i '/ILoveCandy/d' /etc/pacman.conf
sudo sed -i '/^#*Color/d' /etc/pacman.conf
sudo sed -i '/\[options\]/a Color\nILoveCandy' /etc/pacman.conf
ok "تم تفعيل Color و ILoveCandy"

# ---- تحديث قاعدة بيانات pacman ----
step "تحديث قاعدة بيانات الحزم"
sudo pacman -Sy --noconfirm || warn "فشل تحديث قاعدة بيانات pacman"

# ---- تحديث النظام & Flatpak ----
install_pacman_checked flatpak
sudo pacman -Syu --noconfirm || true
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
flatpak update --appstream -y || true

# ========================= تثبيت الحزم حسب الفئة =========================

# ---- الأساسيات (Essential) ----
# كل الحزم الضرورية للنظام والبرامج المهمة
install_pacman_checked \
  mpv \               # وسائط
  git \               # تطوير
  base-devel \        # تطوير
  pacman-contrib \    # نظامي
  noto-fonts \        # خطوط
  noto-fonts-emoji \  # خطوط
  ttf-dejavu \        # خطوط
  ttf-liberation \    # خطوط
  networkmanager \    # نظامي
  ufw \               # نظامي
  power-profiles-daemon \ # نظامي
  ntp \               # نظامي
  cups \              # نظامي
  cups-pdf \          # نظامي
  system-config-printer \ # نظامي
  xdg-user-dirs \     # نظامي
  partitionmanager \  # نظامي
  wget \              # أداة مساعدة
  curl \              # أداة مساعدة
  btrfs-progs \       # ملفات
  xfsprogs \          # ملفات
  f2fs-tools \        # ملفات
  exfatprogs \        # ملفات
  ntfs-3g \           # ملفات
  dosfstools \        # ملفات
  mtools \            # ملفات
  udftools \          # ملفات
  unzip \             # ضغط
  zip \               # ضغط
  unrar               # ضغط
ok "تم تثبيت الحزم الأساسية"

# Flatpak أساسي
flatpak install -y flathub com.github.iwalton3.jellyfin-mpv-shim \ # وسائط
flatpak install -y flathub org.nickvision.tubeconverter             # وسائط

# AUR أساسي
ensure_paru
install_aur_failsafe \
  zen-browser-bin \       # تصفح
  ffmpegthumbs-git        # وسائط
ok "تم تثبيت الحزم الأساسية من AUR"

# ---- الاختيارية (Optional) ----
# الحزم الترفيهية أو إضافات اختيارية
install_pacman_checked \
  mkvtoolnix-gui \    # وسائط
  fastfetch \         # نظامي
  qbittorrent \       # وسائط
  gwenview \          # وسائط
  discord \           # تواصل
  lutris \            # ألعاب
  gamescope \         # ألعاب
  lib32-mangohud \    # ألعاب
  gamemode \           # ألعاب
  lib32-gamemode \    # ألعاب
  goverlay            # ألعاب
ok "تم تثبيت الحزم الاختيارية"

install_aur_failsafe \
  autosubsync-bin \       # وسائط
  renamemytvseries-qt-bin \ # وسائط
  subtitlecomposer \       # وسائط
  bauh \                   # إدارة برامج
  visual-studio-code-bin \ # تطوير
  spotify \                # ترفيه
  flatseal \               # أداة مساعدة
  jellyfin-media-player \  # وسائط
  proton-ge-custom-bin     # ألعاب
ok "تم تثبيت الحزم الاختيارية من AUR"

# ---- تفعيل الخدمات الأساسية ----
SERVICES=(ufw.service power-profiles-daemon.service NetworkManager.service fstrim.timer paccache.timer cups.service)
for svc in "${SERVICES[@]}"; do enable_service "$svc"; done
sudo ufw enable || true
sudo timedatectl set-ntp true || true

# ---- تنظيف النظام Ultimate Cleanup ----
step "تشغيل التنظيف النهائي"
sudo pacman -Syu --noconfirm
sudo paccache -r -k 30 || true
ORPHANS=$(pacman -Qdtq || true)
[[ -n "$ORPHANS" ]] && sudo pacman -Rns --noconfirm $ORPHANS
[[ -d ~/.cache/paru ]] && rm -rf ~/.cache/paru/* || true
flatpak uninstall --unused --assumeyes || true
sudo journalctl --vacuum-time="7d" || true
sudo find /tmp -type f -mtime +7 -delete || true
sudo find /var/tmp -type f -mtime +7 -delete || true
sudo find /var/log -type f -size +100M -exec rm -f {} + 2>/dev/null || true
ok "✅ تنظيف النظام خلص"

# ---- نهاية ----
END_TIME=$(date +'%F %T')
ok "✨ خلصنا! بدأ: $START_TIME — انتهى: $END_TIME"
[[ -s "$MISSING_PKGS_FILE" ]] && warn "📦 حزم مفقودة: $MISSING_PKGS_FILE"