#!/bin/bash

set -e

echo "🚀 بدء التثبيت من Flathub..."

# تحديد مدير الحزم حسب التوزيعة
if command -v dnf &>/dev/null; then
  PKG_INSTALL="sudo dnf install -y"
  DISTRO="fedora"
elif command -v pacman &>/dev/null; then
  PKG_INSTALL="sudo pacman -S --needed --noconfirm"
  DISTRO="arch"
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
echo "🐦 تثبيت tailscale..."
if [[ "$DISTRO" == "fedora" ]]; then
  echo "➕ إضافة مستودع tailscale الرسمي لفيدورا..."
  sudo dnf config-manager --add-repo https://pkgs.tailscale.com/stable/fedora/tailscale.repo
  $PKG_INSTALL tailscale

elif [[ "$DISTRO" == "arch" ]]; then
  if ! command -v yay &>/dev/null; then
    echo "🛠️ جارِ تثبيت yay (AUR helper)..."
    $PKG_INSTALL git base-devel
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ..
    rm -rf yay
  else
    echo "✅ yay موجود بالفعل، تخطى التثبيت."
  fi

  yay -S --noconfirm tailscale-bin
fi

echo "✅ تم التثبيت بنجاح!"
