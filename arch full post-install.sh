#!/bin/bash
set -euo pipefail

# =========================
# Arch Post Install - Clean & Auto (Non-Interactive, AUR-safe)
# =========================

# ---- Config ----
AUR_TIMEOUT=${AUR_TIMEOUT:-180}
PARU_MAKE_TIMEOUT=${PARU_MAKE_TIMEOUT:-300}
FLATPAK_TIMEOUT=${FLATPAK_TIMEOUT:-180}

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
install_pacman_checked flatpak
sudo pacman -Syu --noconfirm || true
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || true
flatpak update --appstream -y || true

# ========================= تثبيت الحزم حسب الأولوية =========================

# ---- المرحلة 1: الحزم الأساسية للنظام ----
step "تثبيت الحزم الأساسية للنظام"
install_pacman_checked \
  archlinux-keyring git base-devel pacman-contrib \
  noto-fonts noto-fonts-emoji ttf-dejavu ttf-liberation
ok "تم تثبيت الحزم الأساسية للنظام"

# ---- المرحلة 2: إدارة النظام والخدمات ----
step "تثبيت أدوات إدارة النظام والخدمات"
install_pacman_checked \
  networkmanager ufw power-profiles-daemon ntp \
  cups cups-pdf system-config-printer
ok "تم تثبيت أدوات إدارة النظام والخدمات"

# ---- المرحلة 3: أدوات مساعدة للنظام والتخصيص ----
step "تثبيت الأدوات المساعدة للنظام"
install_pacman_checked \
  xdg-user-dirs partitionmanager wget curl
ok "تم تثبيت الأدوات المساعدة للنظام"

# ---- المرحلة 4: دعم صيغ الملفات والأقراص ----
step "تثبيت أدوات دعم صيغ الملفات والأقراص"
install_pacman_checked \
  btrfs-progs xfsprogs f2fs-tools exfatprogs ntfs-3g \
  dosfstools mtools udftools unzip zip unrar
ok "تم تثبيت دعم صيغ الملفات والأقراص"

# ---- المرحلة 5: برامج الوسائط والتسلية ----
step "تثبيت برامج الوسائط"
install_pacman_checked \
  mpv mkvtoolnix-gui fastfetch qbittorrent gwenview discord
ok "تم تثبيت برامج الوسائط والتسلية"

# ---- المرحلة 6: ألعاب وتحسينات الأداء ----
step "تثبيت أدوات الألعاب وتحسين الأداء"
install_pacman_checked \
  lutris gamescope lib32-mangohud gamemode lib32-gamemode goverlay
ok "تم تثبيت أدوات الألعاب"

# ---- المرحلة 7: برامج Flatpak ----
step "تثبيت برامج Flatpak"
flatpak install -y flathub com.github.iwalton3.jellyfin-mpv-shim || true
flatpak install -y flathub org.nickvision.tubeconverter || true
ok "تم تثبيت برامج Flatpak"

# ---- المرحلة 8: حزم AUR حسب الأولوية ----
ensure_paru

# المرحلة 1: أساسية لتشغيل برامج مهمة
step "تثبيت AUR الأساسية لتشغيل برامج مهمة"
install_aur_failsafe \
  jellyfin-media-player \
  proton-ge-custom-bin
ok "تم تثبيت الحزم الأساسية لتشغيل البرامج"

# المرحلة 2: تحسينات وأدوات مساعدة
step "تثبيت AUR تحسينات وأدوات مساعدة"
install_aur_failsafe \
  ffmpegthumbs-git \
  autosubsync-bin \
  renamemytvseries-qt-bin \
  subtitlecomposer
ok "تم تثبيت الحزم المساعدة"

# المرحلة 3: برامج تطوير وإدارة
step "تثبيت AUR برامج تطوير وإدارة"
install_aur_failsafe \
  visual-studio-code-bin \
  bauh
ok "تم تثبيت برامج التطوير والإدارة"

# المرحلة 4: برامج اختيارية وترفيهية
step "تثبيت AUR برامج اختيارية وترفيهية"
install_aur_failsafe \
  zen-browser-bin \
  spotify \
  flatseal
ok "تم تثبيت البرامج الاختيارية والترفيهية"

# ---- SpotX ----
step "تعديل Spotify ب SpotX"
bash <(curl -sSL https://spotx-official.github.io/run.sh) || warn "فشل تشغيل SpotX"
ok "Spotify اتظبط ب SpotX"

# ---- تفعيل الخدمات الأساسية ----
step "تفعيل الخدمات"
SERVICES=(ufw.service power-profiles-daemon.service NetworkManager.service fstrim.timer paccache.timer cups.service)
for svc in "${SERVICES[@]}"; do enable_service "$svc"; done
sudo ufw enable || true
sudo timedatectl set-ntp true || true

# ---- تنظيف النظام Ultimate Cleanup ----
step "تشغيل سكربت التنظيف Ultimate Cleanup"
PACMAN_CACHE_DAYS=30
JOURNAL_DAYS=7
TMP_DAYS=7
LOG_SIZE_LIMIT=100M

sudo pacman -Syu --noconfirm
sudo find /var/cache/pacman/pkg/ -type d -name "download-*" -exec rm -rf {} + 2>/dev/null
sudo find /var/cache/pacman/pkg/ -type f -exec rm -f {} + 2>/dev/null
sudo paccache -r -k "${PACMAN_CACHE_DAYS}" || true

ORPHANS=$(pacman -Qdtq || true)
if [ -n "$ORPHANS" ]; then
    sudo pacman -Rns --noconfirm $ORPHANS
fi

if command -v paru &>/dev/null; then
    rm -rf ~/.cache/paru/* ~/.cache/paru/clone ~/.cache/paru/diff || true
    paru -Sc --noconfirm || true
fi

if command -v flatpak &>/dev/null; then
    flatpak uninstall --unused --assumeyes || true
    flatpak repair || true
fi

sudo journalctl --vacuum-time="${JOURNAL_DAYS}d" || true
sudo find /tmp -type f -mtime +${TMP_DAYS} -delete || true
sudo find /var/tmp -type f -mtime +${TMP_DAYS} -delete || true
sudo find /var/log -type f -size +${LOG_SIZE_LIMIT} -exec rm -f {} + 2>/dev/null || true

ok "✅ انتهى تنظيف النظام Ultimate Non-Interactive!"

# ---- نهاية ----
END_TIME=$(date +'%F %T')
ok "✨ خلصنا! بدأ: $START_TIME — انتهى: $END_TIME"
[[ -s "$MISSING_PKGS_FILE" ]] && warn "📦 حزم مفقودة: $MISSING_PKGS_FILE"