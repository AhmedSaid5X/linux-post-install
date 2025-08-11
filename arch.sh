#!/bin/bash
set -e

echo "🚀 تثبيت خطوط Arch + دعم العربى..."

# --- تثبيت yay لو مش موجود ---
if ! command -v yay &>/dev/null; then
  echo "🛠️ تثبيت yay (AUR helper)..."
  sudo pacman -S --needed --noconfirm git base-devel
  tmpdir=$(mktemp -d)
  git clone https://aur.archlinux.org/yay-bin.git "$tmpdir/yay-bin"
  cd "$tmpdir/yay-bin"
  makepkg -si --noconfirm
  cd ~
  rm -rf "$tmpdir"
fi

# --- تثبيت خطوط من الريبو الرسمى ---
echo "📦 تثبيت الخطوط من المستودع الرسمى..."
sudo pacman -S --needed --noconfirm \
  noto-fonts \
  noto-fonts-emoji \
  noto-fonts-extra \
  ttf-dejavu \
  ttf-liberation \
  ttf-scheherazade-new

# --- تثبيت خطوط من الـ AUR ---
echo "📦 تثبيت الخطوط من الـ AUR..."
yay -S --needed --noconfirm \
  ttf-amiri \
  ttf-sil-harmattan

echo "✅ تم تثبيت كل الخطوط بنجاح."
echo "ℹ️ اعمل Log out أو ريستارت عشان التغييرات تتفعل."
