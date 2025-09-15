#!/bin/bash
set -euo pipefail

# =========================
# Arch Post Install - Essential vs Optional with package classification
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

# ---- كل الحزم مع التصنيف والتعليقات ----
# Essential
install_pacman_checked \
  mpv \                     # وسائط: مشغل فيديو
  git \                     # تطوير: أدوات git
  base-devel \              # تطوير: أدوات build
  pacman-contrib \          # نظامي: أدوات pacman مساعدة
  noto-fonts \              # خطوط: نصوص عامة
  noto-fonts-emoji \        # خطوط: إيموجي
  ttf-dejavu \              # خطوط
  ttf-liberation \          # خطوط
  networkmanager \          # نظامي: إدارة الشبكات
  ufw \                     # نظامي: جدار حماية
  power-profiles-daemon \   # نظامي: إدارة الطاقة
  ntp \                     # نظامي: مزامنة الوقت
  cups \                    # نظامي: الطباعة
  cups-pdf \                # نظامي: الطباعة PDF
  system-config-printer \   # نظامي: إعداد الطابعات
  xdg-user-dirs \           # نظامي: إنشاء مجلدات المستخدم
  partitionmanager \        # نظامي: إدارة الأقراص
  wget \                     # أداة مساعدة: تحميل
  curl \                     # أداة مساعدة: تحميل
  btrfs-progs \              # ملفات: دعم BTRFS
  xfsprogs \                 # ملفات: دعم XFS
  f2fs-tools \               # ملفات: دعم F2FS
  exfatprogs \               # ملفات: دعم exFAT
  ntfs-3g \                  # ملفات: دعم NTFS
  dosfstools \               # ملفات: دعم FAT
  mtools \                   # ملفات: أدوات FAT
  udftools \                 # ملفات: دعم UDF
  unzip \                    # ضغط: unzip
  zip \                      # ضغط: zip
  unrar                       # ضغط: unrar
ok "تم تثبيت الحزم الأساسية"

# Flatpak Essential
flatpak install -y flathub com.github.iwalton3.jellyfin-mpv-shim \ # وسائط: تشغيل Jellyfin مع MPV
flatpak install -y flathub org.nickvision.tubeconverter             # وسائط: تحويل الفيديو

# AUR Essential
ensure_paru
install_aur_failsafe \
  zen-browser-bin \       # تصفح: متصفح Zen
  ffmpegthumbs-git        # وسائط: توليد مصغرات الفيديو
ok "تم تثبيت الحزم الأساسية من AUR"

# Optional
install_pacman_checked \
  mkvtoolnix-gui \          # وسائط: تعديل MKV
  fastfetch \               # نظامي: عرض مواصفات النظام
  qbittorrent \             # وسائط: تحميل تورنت
  gwenview \                # وسائط: عرض الصور
  discord \                 # تواصل: دردشة
  lutris \                  # ألعاب: منصة ألعاب
  gamescope \               # ألعاب: تحسين الألعاب
  lib32-mangohud \          # ألعاب: HUD للألعاب
  gamemode \                 # ألعاب: تحسين الأداء
  lib32-gamemode \          # ألعاب: نسخة 32-bit
  goverlay                  # ألعاب: overlays
ok "تم تثبيت الحزم الاختيارية"

install_aur_failsafe \
  autosubsync-bin \          # وسائط: مزامنة الترجمة
  renamemytvseries-qt-bin \  # وسائط: إعادة تسمية المسلسلات
  subtitlecomposer \         # وسائط: تحرير الترجمة
  bauh \                      # إدارة: إدارة برامج
  visual-studio-code-bin \    # تطوير: محرر برمجي
  spotify \                   # ترفيه: موسيقى
  flatseal \                  # أداة: إدارة صلاحيات Flatpak
  jellyfin-media-player \     # وسائط: تشغيل Jellyfin
  proton-ge-custom-bin        # ألعاب: تشغيل ألعاب ويندوز
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