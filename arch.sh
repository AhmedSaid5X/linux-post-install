#!/bin/bash
set -e

echo "🚀 بدء تثبيت خطوط Arch + دعم العربي..."

# تثبيت الخطوط من المستودعات الرسمية
echo "📦 تثبيت الخطوط من المستودع الرسمي..."
sudo pacman -S --needed --noconfirm noto-fonts noto-fonts-emoji noto-fonts-extra ttf-dejavu ttf-liberation ttf-scheherazade-new

# تثبيت الخطوط من AUR (تأكد من وجود yay)
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

echo "🚀 تثبيت البرامج المطلوبة..."

# قائمة البرامج الرسمية من مستودعات Arch (مع telegram-desktop)
OFFICIAL_PACKAGES=(
  fastfetch
  flatpak
  mpv
  podman-desktop
  curl
  mkvtoolnix-cli
  telegram-desktop
)

# تثبيت البرامج الرسمية
for pkg in "${OFFICIAL_PACKAGES[@]}"; do
  echo "تثبيت $pkg ..."
  sudo pacman -S --needed --noconfirm "$pkg"
done

# برامج من AUR
AUR_PACKAGES=(
  spotify
  subtitlecomposer
  upscayl
)

echo "📦 تثبيت برامج من AUR..."
for pkg in "${AUR_PACKAGES[@]}"; do
  echo "تثبيت $pkg ..."
  yay -S --needed --noconfirm "$pkg"
done

# تأكد من تثبيت flatpak
if ! command -v flatpak &>/dev/null; then
  echo "🛠️ تثبيت flatpak..."
  sudo pacman -S --needed --noconfirm flatpak
fi

echo "✅ السكربت خلص. اضغط Enter للخروج..."
read -r
