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

echo "🚀 تثبيت البرامج المطلوبة..."

# تثبيت البرامج من الريبو الرسمي
sudo pacman -S --needed --noconfirm \
  fastfetch \
  flatpak \
  mpv \
  telegram-desktop \
  discord \
  mkvtoolnix \
  qbittorrent \
  spotify \
  subtitlecomposer \
  upscayl \
  podman-desktop \
  curl

# تثبيت البرامج من الـ AUR عبر yay
yay -S --needed --noconfirm \
  flatseal \
  jellyfin-media-player \
  jellyfin-mpv-shim \
  warehouse-bin \
  mission-center-bin

# تثبيت tailscale عن طريق السكربت الرسمي
echo "🌐 تثبيت tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

echo "✅ تم تثبيت كل الخطوط والبرامج بنجاح."
echo "ℹ️ يُفضل تعمل Log out أو ريستارت عشان التغييرات تتفعل."
