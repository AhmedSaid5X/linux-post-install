#!/bin/bash
set -e

# تأكد من وجود yay (AUR helper)
install_yay() {
  if ! command -v yay &>/dev/null; then
    echo "🛠️ تثبيت yay (AUR helper)..."
    sudo pacman -S --needed --noconfirm git base-devel
    tmpdir=$(mktemp -d)
    git clone https://aur.archlinux.org/yay-bin.git "$tmpdir"
    cd "$tmpdir"
    makepkg -si --noconfirm
    cd -
    rm -rf "$tmpdir"
  fi
}

# تأكد من وجود flatpak
install_flatpak() {
  if ! command -v flatpak &>/dev/null; then
    echo "🛠️ تثبيت flatpak..."
    sudo pacman -S --needed --noconfirm flatpak
  fi
}

# إضافة مستودع Flathub لو مش مضاف
add_flathub_repo() {
  if ! flatpak remote-list | grep -q "^flathub$"; then
    echo "🌐 إضافة مستودع Flathub..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  fi
}

echo "🚀 تثبيت yay والخطوط..."

install_yay

sudo pacman -S --needed --noconfirm noto-fonts noto-fonts-emoji noto-fonts-extra ttf-dejavu ttf-liberation ttf-scheherazade-new
yay -S --needed --noconfirm ttf-amiri ttf-sil-harmattan

install_flatpak
add_flathub_repo

echo "✅ انتهى التثبيت. اضغط Enter للخروج..."
read -r -p ""
