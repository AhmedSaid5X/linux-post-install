#!/bin/bash

set -e

echo "🚀 بدء التثبيت من Flathub على Arch..."

# التأكد إن flatpak متسطب
if ! command -v flatpak &> /dev/null; then
  echo "🛠️ جارِ تثبيت flatpak..."
  sudo pacman -S --needed --noconfirm flatpak
fi

# التأكد إن yay متسطب (AUR helper)
if ! command -v yay &> /dev/null; then
  echo "🛠️ جارِ تثبيت yay..."
  sudo pacman -S --needed --noconfirm git base-devel
  git clone https://aur.archlinux.org/yay.git
  cd yay
  makepkg -si --noconfirm
  cd ..
  rm -rf yay
fi

# إضافة Flathub لو مش متضاف
if ! flatpak remotes | grep -q flathub; then
  echo "➕ إضافة Flathub..."
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

# تحديد نوع الواجهة
desktop_env=$(echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]')
echo "🖥️ الواجهة الحالية: $desktop_env"

# لو الواجهة GNOME، نسطب gnome-tweaks
if [[ "$desktop_env" == *gnome* ]]; then
  echo "🛠️ جارِ تثبيت GNOME Tweaks..."
  sudo pacman -S --needed --noconfirm gnome-tweaks
fi

# قائمة البرامج الأساسية من Flathub
apps=(
  com.visualstudio.code
  org.telegram.desktop
  com.discordapp.Discord
  com.github.tchx84.Flatseal
  com.heroicgameslauncher.hgl
  com.github.iwalton3.jellyfin-media-player
  com.github.iwalton3.jellyfin-mpv-shim
  org.bunkus.mkvtoolnix-gui
  org.qbittorrent.qBittorrent
  com.spotify.Client
  org.kde.subtitlecomposer
  io.github.flattool.Warehouse
  org.upscayl.Upscayl
  io.missioncenter.MissionCenter
  io.podman_desktop.PodmanDesktop
  io.mpv.Mpv
)

# لو GNOME نضيف Extension Manager
if [[ "$desktop_env" == *gnome* ]]; then
  echo "🧩 إضافة Extension Manager..."
  apps+=(com.mattjakeman.ExtensionManager)
else
  echo "🧹 تخطى أدوات GNOME (الواجهة مش GNOME)."
fi

# تثبيت البرامج من Flathub
for app in "${apps[@]}"; do
  echo "📦 تثبيت $app ..."
  flatpak install -y flathub "$app"
done

# تثبيت tailscale (من AUR)
echo "🐦 تثبيت tailscale..."
yay -S --needed --noconfirm tailscale

echo "✅ تم التثبيت بنجاح!"
