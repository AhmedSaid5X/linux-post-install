#!/bin/bash
set -e

# نتأكد إن yay موجود، لو مش موجود نثبته
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

# تثبيت البرامج من AUR
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

# تثبيت mkvtoolnix من المستودع الرسمي (community)
echo "📦 تثبيت mkvtoolnix من المستودع الرسمي..."
sudo pacman -S --needed --noconfirm mkvtoolnix-cli

# تثبيت Flatpak إذا مش موجود
if ! command -v flatpak &>/dev/null; then
  echo "🛠️ تثبيت flatpak..."
  sudo pacman -S --needed --noconfirm flatpak
fi

# تثبيت بعض البرامج عن طريق Flatpak لو محتاج
# (مثلاً ممكن تضيف برامج مش متوفرة في AUR أو مستودعات)
# flatpak install -y flathub some.flatpak.App

echo "✅ تم التثبيت بنجاح."
