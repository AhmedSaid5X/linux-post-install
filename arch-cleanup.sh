#!/bin/bash
set -euo pipefail

# =========================
# Arch Ultimate Cleanup - Fully Non-Interactive
# =========================

PACMAN_KEEP_VERSIONS=3
JOURNAL_DAYS=7
TMP_DAYS=7
LOG_SIZE_LIMIT=100M

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