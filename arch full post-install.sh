#!/bin/bash
set -euo pipefail
trap 'echo "❌ حدث خطأ أثناء تنفيذ السكربت"; exit 1' ERR

START_TIME=$(date +'%F %T')

# =========================
# Fix pacman lock
# =========================
if pgrep -x pacman >/dev/null; then
    echo "❌ فيه عملية pacman شغالة دلوقتي — اقفلها الأول أو استنى تخلص."
    exit 1
fi

if [[ -f /var/lib/pacman/db.lck ]]; then
    echo "⚠️ لقينا pacman lock قديم — هنشيله دلوقتي..."
    sudo rm -f /var/lib/pacman/db.lck
fi

# =========================
# Functions
# =========================
step() { echo -e "\n🔹 $1..."; }
ok()   { echo "✅ $1"; }
warn() { echo "⚠️ $1"; }

enable_service() {
    local svc="$1"
    if systemctl list-unit-files | grep -q "^$svc"; then
        if ! systemctl is-enabled --quiet "$svc"; then
            sudo systemctl enable --now "$svc" || true
            ok "تم تفعيل $svc"
        else
            ok "$svc مفعل بالفعل"
        fi
    else
        warn "$svc غير موجود"
    fi
}

# =========================
# 1️⃣ تفعيل الألوان و ILoveCandy
# =========================
step "تفعيل الألوان و ILoveCandy في pacman.conf"
sudo sed -i '/ILoveCandy/d' /etc/pacman.conf
sudo sed -i '/^#*Color/d' /etc/pacman.conf
sudo sed -i '/\[options\]/a Color\nILoveCandy' /etc/pacman.conf
ok "تم تفعيل الألوان و ILoveCandy"

# =========================
# 2️⃣ تحديث النظام مرة واحدة
# =========================
step "تحديث النظام"
sudo pacman -Syu --noconfirm
ok "النظام محدث"

# =========================
# 3️⃣ تثبيت paru (AUR helper) مع retry/check
# =========================
step "تثبيت paru"
if ! command -v paru &>/dev/null; then
    sudo pacman -S --needed --noconfirm git base-devel
    if ! git clone https://aur.archlinux.org/paru.git /tmp/paru; then
        warn "تعذر استنساخ AUR repo، حاول مرة أخرى"
        exit 1
    fi
    (cd /tmp/paru && makepkg -si --noconfirm) || { warn "فشل تثبيت paru"; exit 1; }
    rm -rf /tmp/paru
    ok "تم تثبيت paru"
else
    ok "paru موجود بالفعل"
fi

# =========================
# 4️⃣ إضافة مستودعات Flatpak مع check
# =========================
step "إضافة Flathub إلى Flatpak"
sudo pacman -S --needed --noconfirm flatpak
if ! sudo flatpak remote-list | grep -q flathub; then
    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo || warn "فشل إضافة Flathub"
fi
ok "تم إضافة Flathub"

# =========================
# 5️⃣ تثبيت الحزم الأساسية
# =========================
step "تثبيت الحزم الأساسية"
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
ok "تم تثبيت الحزم الأساسية"

# =========================
# 6️⃣ تثبيت حزم من AUR
# =========================
step "تثبيت الحزم من AUR"
paru -S --needed --noconfirm ffmpegthumbs-git zen-browser-bin bauh spotify
ok "تم تثبيت حزم AUR"

# =========================
# 7️⃣ تثبيت SpotX
# =========================
step "تثبيت SpotX"
bash <(curl -sSL https://spotx-official.github.io/run.sh)
ok "تم تثبيت SpotX"

# =========================
# 8️⃣ تثبيت الحزم الاختيارية
# =========================
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
    step "تثبيت الحزم الاختيارية"
    sudo pacman -S --needed --noconfirm "${pacman_optional[@]}"
    paru -S --needed --noconfirm "${aur_optional[@]}"
    flatpak install -y flathub "${flatpak_optional[@]}" || true
    ok "تم تثبيت كل الحزم الاختيارية"
else
    warn "تم تخطي الحزم الاختيارية"
fi

# =========================
# 9️⃣ تفعيل الخدمات مع check
# =========================
step "تفعيل الخدمات"
SERVICES=(
    "ufw.service"
    "power-profiles-daemon.service"
    "fstrim.timer"
    "paccache.timer"
)
for svc in "${SERVICES[@]}"; do
    enable_service "$svc"
done

sudo ufw status | grep -q "active" || sudo ufw enable
sudo timedatectl set-ntp true || true
ok "تم تفعيل كل الخدمات المهمة"

# =========================
# 🔟 تنظيف النظام Ultimate Non-Interactive
# =========================
step "بدء تنظيف النظام Ultimate Cleanup"

PACMAN_KEEP_VERSIONS=3
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
sudo paccache -r -k "${PACMAN_KEEP_VERSIONS}" || true

# إزالة الحزم orphan
ORPHANS=$(pacman -Qdtq || true)
if [ -n "$ORPHANS" ]; then
    echo "🗑 إزالة الحزم orphan..."
    sudo pacman -Rns --noconfirm $ORPHANS
fi

# تنظيف AUR helper (paru)
if command -v paru &>/dev/null; then
    echo "🗑 تنظيف Paru cache بالكامل..."
    rm -rf ~/.cache/paru/* ~/.cache/paru/clone ~/.cache/paru/diff || true
    paru -Sc --noconfirm || true
fi

# تنظيف Flatpak
if command -v flatpak &>/dev/null; then
    echo "🗑 تنظيف flatpak..."
    flatpak uninstall --unused --assumeyes || true
    flatpak repair || true
fi

# تنظيف systemd journal
echo "📜 تنظيف journal..."
sudo journalctl --vacuum-time="${JOURNAL_DAYS}d" || true

# تنظيف ملفات temp القديمة
echo "🧹 تنظيف /tmp و /var/tmp..."
sudo find /tmp -type f -mtime +${TMP_DAYS} -delete || true
sudo find /var/tmp -type f -mtime +${TMP_DAYS} -delete || true

# حذف ملفات log الكبيرة
echo "📂 حذف ملفات log الكبيرة (> ${LOG_SIZE_LIMIT})..."
sudo find /var/log -type f -size +${LOG_SIZE_LIMIT} -exec rm -f {} + 2>/dev/null || true

ok "انتهى تنظيف النظام"

END_TIME=$(date +'%F %T')
echo -e "\n✨ خلصنا! بدأ: $START_TIME — انتهى: $END_TIME"