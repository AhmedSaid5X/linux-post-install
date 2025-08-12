#!/bin/bash
set -e

echo "🚀 بدء التثبيت..."

# إضافة Flathub (قبل التثبيت)
sudo pacman -Syu --needed --noconfirm flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# تثبيت الحزم الأساسية من pacman
sudo pacman -S --needed --noconfirm \
  git base-devel pacman-contrib \
  noto-fonts noto-fonts-emoji noto-fonts-extra \
  ttf-dejavu ttf-liberation ttf-scheherazade-new \
  mpv mkvtoolnix-gui firefox

# تثبيت yay لو مش موجود
if ! command -v yay &>/dev/null; then
  tmpdir=$(mktemp -d)
  git clone https://aur.archlinux.org/yay-bin.git "$tmpdir"
  cd "$tmpdir"
  makepkg -si --noconfirm
  cd -
  rm -rf "$tmpdir"
fi

# تثبيت حزم من AUR
yay -S --needed --noconfirm \
  ttf-amiri ttf-sil-harmattan ffmpegthumbs-git

echo "🧹 بدء التنظيف..."

# تنظيف كاش pacman
sudo paccache -r

# حذف الحزم اليتيمة
sudo pacman -Rns --noconfirm $(pacman -Qtdq || true)

# تنظيف كاش AUR
yay -Sc --noconfirm

# تنظيف logs
sudo journalctl --vacuum-time=7d

# تنظيف flatpak
flatpak uninstall --unused -y

echo "✨ تم التثبيت والتنظيف بنجاح! 🚀"
