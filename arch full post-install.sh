#!/bin/bash
set -euo pipefail

START_TIME=$(date +'%F %T')
LOG_FILE="$HOME/arch-post-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "🟢 بدء السكربت Non-Interactive: $START_TIME"

# ------------------------------
# 1️⃣ تفعيل الألوان وILoveCandy
# ------------------------------
echo "🔧 تفعيل الألوان وILoveCandy في pacman.conf..."
sudo sed -i '/ILoveCandy/d' /etc/pacman.conf
sudo sed -i '/^#*Color/d' /etc/pacman.conf
sudo sed -i '/\[options\]/a Color\nILoveCandy' /etc/pacman.conf
echo "✅ تم تفعيل الألوان وILoveCandy"

# ------------------------------
# 2️⃣ تحديث النظام
# ------------------------------
echo "🔄 تحديث قاعدة بيانات الحزم..."
sudo pacman -Syu --noconfirm

# ------------------------------
# 3️⃣ تثبيت paru (AUR helper)
# ------------------------------
echo "📦 تثبيت paru..."
sudo pacman -S --needed --noconfirm git base-devel
cd /tmp
git clone https://aur.archlinux.org/paru.git
cd paru
makepkg -si --noconfirm
cd ~
rm -rf /tmp/paru
echo "✅ تم تثبيت paru"

# ------------------------------
# 4️⃣ إضافة مستودعات Flatpak
# ------------------------------
echo "🌐 إضافة Flathub إلى Flatpak..."
sudo pacman -S --needed --noconfirm flatpak
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
echo "✅ تم إضافة Flathub"

# ------------------------------
# 5️⃣ تثبيت الحزم الأساسية من pacman
# ------------------------------
echo "📦 تثبيت الحزم الأساسية..."
sudo pacman -S --needed --noconfirm \
base-devel pacman-contrib \
noto-fonts noto-fonts-emoji timeshift \
ttf-dejavu ttf-liberation \
fastfetch ntp gwenview \
btrfs-progs xfsprogs f2fs-tools exfatprogs ntfs-3g \
dosfstools mtools udftools unzip \
partitionmanager hyphen-en \
power-profiles-daemon ufw unrar zip \
mpv
echo "✅ تم تثبيت كل الحزم الأساسية"

# ------------------------------
# 6️⃣ تثبيت الحزم من AUR
# ------------------------------
echo "📦 تثبيت الحزم من AUR..."
paru -S --needed --noconfirm ffmpegthumbs-git zen-browser-bin bauch
echo "✅ تم تثبيت كل حزم AUR"

# ------------------------------
# 7️⃣ تثبيت Spotify
# ------------------------------
echo "🎵 تثبيت Spotify..."
bash <(curl -sSL https://spotx-official.github.io/run.sh)
echo "✅ تم تثبيت Spotify"

# ------------------------------
# 8️⃣ تثبيت كل الحزم الاختيارية مع سؤال واحد
# ------------------------------
pacman_optional=(
    "mkvtoolnix-gui" "discord" "lutris" "gamescope"
    "lib32-mangohud" "gamemode" "lib32-gamemode" "goverlay"
)
aur_optional=(
    "proton-ge-custom-bin" "autosubsync-bin" "renamemytvseries-qt-bin"
    "jellyfin-media-player" "subtitlecomposer" "visual-studio-code-bin"
)
flatpak_optional=(
    "com.github.iwalton3.jellyfin-mpv-shim" "org.nickvision.tubeconverter"
)

read -p "⚡ هل تريد تثبيت كل الحزم الاختيارية؟ (y/n): " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    echo "⚡ جاري تثبيت الحزم الاختيارية..."

    # pacman
    sudo pacman -S --needed --noconfirm "${pacman_optional[@]}"

    # AUR
    paru -S --needed --noconfirm "${aur_optional[@]}"

    # Flatpak
    for pkg in "${flatpak_optional[@]}"; do
        flatpak install -y flathub "$pkg" || true
    done

    echo "✅ تم تثبيت كل الحزم الاختيارية"
else
    echo "⚡ تم تخطي تثبيت الحزم الاختيارية"
fi

# ------------------------------
# 9️⃣ تفعيل الخدمات تلقائيًا
# ------------------------------
echo "⚡ تفعيل الخدمات..."
SERVICES=(
    "ufw.service"
    "power-profiles-daemon.service"
    "fstrim.timer"
    "paccache.timer"
)
enable_service() {
    local svc="$1"
    if systemctl list-unit-files | grep -q "^$svc"; then
        sudo systemctl enable --now "$svc" || true
        echo "✅ تم تفعيل $svc"
    fi
}
for svc in "${SERVICES[@]}"; do
    enable_service "$svc"
done

sudo ufw enable || true
sudo timedatectl set-ntp true || true
echo "✅ تم تفعيل كل الخدمات المهمة"

# ------------------------------
# 🔟 تنظيف النظام Ultimate Non-Interactive
# ------------------------------
echo "🧹 بدء تنظيف النظام Ultimate Cleanup..."

PACMAN_CACHE_DAYS=30
JOURNAL_DAYS=7
TMP_DAYS=7
LOG_SIZE_LIMIT=100M

sudo pacman -Syu --noconfirm

# pacman cache
sudo find /var/cache/pacman/pkg/ -type d -name "download-*" -exec rm -rf {} + 2>/dev/null
sudo find /var/cache/pacman/pkg/ -type f -exec rm -f {} + 2>/dev/null
sudo paccache -r -k "${PACMAN_CACHE_DAYS}" || true

# إزالة orphan
ORPHANS=$(pacman -Qdtq || true)
if [ -n "$ORPHANS" ]; then
    sudo pacman -Rns --noconfirm $ORPHANS
fi

# تنظيف paru
if command -v paru &>/dev/null; then
    rm -rf ~/.cache/paru/* ~/.cache/paru/clone ~/.cache/paru/diff || true
    paru -Sc --noconfirm || true
fi

# تنظيف flatpak
if command -v flatpak &>/dev/null; then
    flatpak uninstall --unused --assumeyes || true
    flatpak repair || true
fi

# journal
sudo journalctl --vacuum-time="${JOURNAL_DAYS}d" || true

# /tmp و /var/tmp
sudo find /tmp -type f -mtime +${TMP_DAYS} -delete || true
sudo find /var/tmp -type f -mtime +${TMP_DAYS} -delete || true

# حذف ملفات log الكبيرة
sudo find /var/log -type f -size +${LOG_SIZE_LIMIT} -exec rm -f {} + 2>/dev/null || true

echo "✅ انتهى تنظيف النظام Ultimate Non-Interactive!"

END_TIME=$(date +'%F %T')
echo "✨ خلصنا! بدأ: $START_TIME — انتهى: $END_TIME"
echo "🔗 كل التفاصيل مسجلة في: $LOG_FILE"