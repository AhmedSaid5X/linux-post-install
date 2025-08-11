#!/bin/bash
set -e

echo "🚀 بدء تثبيت الخطوط + البرامج..."

# تثبيت الخطوط من المستودعات الرسمية
echo "📦 تثبيت الخطوط من المستودع الرسمي..."
sudo pacman -S --needed --noconfirm noto-fonts noto-fonts-emoji noto-fonts-extra ttf-dejavu ttf-liberation ttf-scheherazade-new

# تثبيت yay لو مش موجود (AUR helper)
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

echo "📦 تثبيت خطوط من AUR..."
yay -S --needed --noconfirm ttf-amiri ttf-sil-harmattan

echo "🚀 تثبيت البرامج الرسمية..."

OFFICIAL_PACKAGES=(
  fastfetch
  flatpak
  mpv
  telegram-desktop
  discord
  mkvtoolnix-cli
  qbittorrent
  podman-desktop
  curl
)

for pkg in "${OFFICIAL_PACKAGES[@]}"; do
  echo "تثبيت $pkg ..."
  sudo pacman -S --needed --noconfirm "$pkg"
done

echo "🚀 تثبيت برامج من AUR..."

AUR_PACKAGES=(
  spotify
  subtitlecomposer
  upscayl
  flatseal
  jellyfin-media-player
  jellyfin-mpv-shim
  warehouse-bin
  mission-center-bin
)

for pkg in "${AUR_PACKAGES[@]}"; do
  echo "تثبيت $pkg ..."
  yay -S --needed --noconfirm "$pkg"
done

# تأكد من تثبيت flatpak (لو حصل مشكلة)
if ! command -v flatpak &>/dev/null; then
  echo "🛠️ تثبيت flatpak..."
  sudo pacman -S --needed --noconfirm flatpak
fi

echo "✅ انتهى التثبيت. اضغط Enter للخروج..."
read -r
