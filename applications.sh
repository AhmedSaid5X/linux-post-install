#!/bin/bash

set -e

echo "🚀 بدء التثبيت من Flathub..."

# تحديد مدير الحزم حسب التوزيعة
if command -v dnf &>/dev/null; then
  PKG_INSTALL="sudo dnf install -y"
elif command -v pacman &>/dev/null; then
  PKG_INSTALL="sudo pacman -S --needed --noconfirm"
else
  echo "❌ مدير الحزم مش مدعوم، السكربت شغال على Fedora أو Arch بس."
  exit 1
fi

# التأكد إن flatpak متسطب
if ! command -v flatpak &> /dev/null; then
  echo "🛠️ جارِ تثبيت flatpak..."
  $PKG_INSTALL flatpak
fi

# إضافة Flathub لو مش متضاف
if ! flatpak remotes | grep -q flathub; then
  echo "➕ إضافة Flathub..."
  sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

# تحديد نوع الواجهة
desktop_env=$(echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]')
echo "🖥️ الواجهة الحالية: $desktop_env"

# لو الواجهة GNOME، نسطب gnome-tweaks
if [[ "$desktop_env" == *gnome* ]]; then
  echo "🛠️ جارِ تثبيت GNOME Tweaks..."
  $PKG_INSTALL gnome-tweaks
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

# تثبيت tailscale
if command -v pacman &>/dev/null; then
  echo "🐦 تثبيت tailscale من pacman..."
  $PKG_INSTALL tailscale
elif command -v dnf &>/dev/null; then
  echo "🐦 تثبيت tailscale من dnf..."
  $PKG_INSTALL tailscale
fi

echo "✅ تم التثبيت بنجاح!"
