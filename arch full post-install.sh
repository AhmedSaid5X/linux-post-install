#!/bin/bash
set -euo pipefail

# =========================
# Logging & UI
# =========================
START_TIME=$(date +'%F %T')
MISSING_PKGS_FILE="$HOME/missing-packages.log"
: > "$MISSING_PKGS_FILE"

step() { echo -e "\n\033[1;36m[$(date +'%H:%M:%S')] ➤ $1\033[0m"; }
ok()   { echo -e "\033[1;32m✔ $1\033[0m"; }
warn() { echo -e "\033[1;33m⚠ $1\033[0m"; }
err()  { echo -e "\033[1;31m✖ $1\033[0m"; }

trap 'err "حصل خطأ! راجع $MISSING_PKGS_FILE"' ERR

# =========================
# Helpers
# =========================
remove_pacman_lock() {
    if [[ -f /var/lib/pacman/db.lck ]]; then
        warn "تم العثور على قفل pacman موجود، جاري إزالته..."
        sudo rm -f /var/lib/pacman/db.lck && ok "تم إزالة قفل pacman."
    fi
}

install_pacman_checked() {
    remove_pacman_lock
    local pkgs=("$@")
    local avail=()
    for pkg in "${pkgs[@]}"; do
        if pacman -Si "$pkg" &>/dev/null; then
            avail+=("$pkg")
        else
            warn "$pkg مش موجود في pacman"
            echo "$pkg" >> "$MISSING_PKGS_FILE"
        fi
    done
    if (( ${#avail[@]} )); then
        sudo pacman -S --noconfirm --needed -q "${avail[@]}"
    fi
}

# =========================
# 1️⃣ تفعيل الألوان وILoveCandy
# =========================
step "تفعيل الألوان وILoveCandy في pacman.conf"
sudo sed -i '/ILoveCandy/d' /etc/pacman.conf
sudo sed -i '/^#*Color/d' /etc/pacman.conf
sudo sed -i '/\[options\]/a Color\nILoveCandy'
ok "تم تفعيل Color وILoveCandy"

# =========================
# 2️⃣ تحديث النظام
# =========================
step "تحديث النظام"
sudo pacman -Syu --noconfirm
ok "تم تحديث النظام"

# =========================
# 3️⃣ تثبيت paru (AUR helper)
# =========================
step "تثبيت paru"
install_pacman_checked git base-devel
tmpdir=$(mktemp -d)
git clone https://aur.archlinux.org/paru.git "$tmpdir/paru"
pushd "$tmpdir/paru" >/dev/null
makepkg -si --noconfirm || warn "فشل makepkg لتثبيت paru"
popd >/dev/null
rm -rf "$tmpdir"
ok "تم تثبيت paru"

# =========================
# 4️⃣ إضافة Flathub
# =========================
step "إضافة Flathub إلى Flatpak"
install_pacman_checked flatpak
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
ok "تم إضافة Flathub"

# =========================
# 5️⃣ تثبيت الحزم الأساسية
# =========================
step "تثبيت الحزم الأساسية"
basic_pkgs=(
base-devel pacman-contrib noto-fonts noto-fonts-emoji timeshift
ttf-dejavu ttf-liberation fastfetch ntp gwenview
btrfs-progs xfsprogs f2fs-tools exfatprogs ntfs-3g
dosfstools mtools udftools unzip partitionmanager hyphen-en
power-profiles-daemon ufw unrar zip mpv
)
install_pacman_checked "${basic_pkgs[@]}"
ok "تم تثبيت الحزم الأساسية"

# =========================
# 6️⃣ تثبيت الحزم الاختيارية مع سؤال واحد
# =========================
pacman_optional=(mkvtoolnix-gui discord lutris gamescope lib32-mangohud gamemode lib32-gamemode goverlay)
aur_optional=(proton-ge-custom-bin autosubsync-bin renamemytvseries-qt-bin jellyfin-media-player subtitlecomposer visual-studio-code-bin)
flatpak_optional=(com.github.iwalton3.jellyfin-mpv-shim org.nickvision.tubeconverter)

read -p "⚡ هل تريد تثبيت كل الحزم الاختيارية؟ (y/n): " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    step "تثبيت الحزم الاختيارية"

    # pacman
    install_pacman_checked "${pacman_optional[@]}"

    # AUR
    for pkg in "${aur_optional[@]}"; do
        if ! paru -Qi "$pkg" &>/dev/null; then
            paru -S --needed --noconfirm "$pkg" || { warn "فشل تثبيت $pkg"; echo "$pkg" >> "$MISSING_PKGS_FILE"; }
        else
            ok "$pkg مثبت بالفعل"
        fi
    done

    # Flatpak
    for pkg in "${flatpak_optional[@]}"; do
        flatpak install -y flathub "$pkg" || true
    done

    ok "تم تثبيت كل الحزم الاختيارية"
else
    warn "تم تخطي تثبيت الحزم الاختيارية"
fi

# =========================
# 7️⃣ تثبيت Spotify + SpotX
# =========================
spotify_check() {
    command -v spotify &>/dev/null
}

step "تثبيت Spotify + SpotX"
if ! spotify_check; then
    if bash <(curl -sSL https://spotx-official.github.io/run.sh); then
        ok "تم تثبيت Spotify + SpotX بنجاح"
    else
        warn "فشل تثبيت Spotify + SpotX"
        echo "spotify / spotx" >> "$MISSING_PKGS_FILE"
    fi
else
    ok "Spotify مثبت بالفعل"
fi

# =========================
# 8️⃣ تفعيل الخدمات الأساسية
# =========================
step "تفعيل الخدمات"
services=(ufw.service power-profiles-daemon.service fstrim.timer paccache.timer)
for svc in "${services[@]}"; do
    if systemctl list-unit-files | grep -q "^$svc"; then
        sudo systemctl enable --now "$svc" || warn "فشل تفعيل $svc"
        ok "تم تفعيل $svc"
    fi
done
sudo ufw enable || true
sudo timedatectl set-ntp true || true
ok "تم تفعيل كل الخدمات المهمة"

# =========================
# 9️⃣ تنظيف النظام Ultimate Cleanup
# =========================
step "تنظيف النظام Ultimate Non-Interactive"
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
orphan_pkgs=$(pacman -Qdtq || true)
if [[ -n "$orphan_pkgs" ]]; then
    sudo pacman -Rns --noconfirm $orphan_pkgs
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

ok "✅ انتهى تنظيف النظام Ultimate Non-Interactive!"

[[ -s "$MISSING_PKGS_FILE" ]] && warn "📦 الحزم المفقودة موجودة في: $MISSING_PKGS_FILE"

END_TIME=$(date +'%F %T')
ok "✨ خلصنا! بدأ: $START_TIME — انتهى: $END_TIME"