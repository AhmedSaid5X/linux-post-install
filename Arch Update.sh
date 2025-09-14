#!/bin/bash

# تحديث مستودعات Arch
echo "🔄 تحديث مستودعات Arch..."
sudo pacman -Syu --noconfirm

# تحديث AUR (باستخدام yay أو paru)
if command -v yay &>/dev/null; then
    echo "🔄 تحديث حزم AUR باستخدام yay..."
    yay -Syu --noconfirm
elif command -v paru &>/dev/null; then
    echo "🔄 تحديث حزم AUR باستخدام paru..."
    paru -Syu --noconfirm
else
    echo "⚠️ لم يتم العثور على yay أو paru لتحديث AUR."
fi

# تحديث Flatpak
if command -v flatpak &>/dev/null; then
    echo "🔄 تحديث حزم Flatpak..."
    flatpak update -y
else
    echo "⚠️ Flatpak مش متسطب."
fi

echo "✅ التحديث خلص كله!"
