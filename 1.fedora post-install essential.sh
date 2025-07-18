#!/bin/bash

set -e

echo "🚀 بدء تجهيز النظام بعد التثبيت..."

# تحديد بيئة سطح المكتب
DESKTOP_ENV=$(echo "${XDG_CURRENT_DESKTOP,,}")

### 1. إضافة RPM Fusion
echo "📦 إضافة RPM Fusion..."
sudo dnf install -y \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

### 2. تثبيت flatpak وإضافة Flathub
echo "📦 تثبيت flatpak..."
sudo dnf install -y flatpak

if ! flatpak remote-list | grep -q flathub; then
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  echo "✅ Flathub تمت إضافته."
else
  echo "✅ Flathub موجود بالفعل."
fi

### 3. تحديث النظام
echo "🔄 تحديث النظام..."
sudo dnf update -y

### 4. استبدال ffmpeg-free بـ ffmpeg الكامل
echo "🎞️ استبدال ffmpeg-free بـ ffmpeg..."
sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing

### 5. تحديث مجموعة multimedia بدون الحزم الضعيفة
echo "🎧 تحديث مجموعة multimedia..."
sudo dnf update -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin

### 6. إصلاح مشاكل GNOME (الثامبنيلز)
if [[ "$DESKTOP_ENV" == *"gnome"* ]]; then
  echo "🔧 GNOME detected: إصلاح الثامبنيلز..."
  sudo dnf install -y \
    ffmpegthumbnailer \
    gstreamer1-libav \
    gstreamer1-plugins-good \
    gstreamer1-plugins-bad-freeworld \
    gstreamer1-plugins-ugly \
    shared-mime-info \
    gnome-desktop4

  echo "🎶 إنشاء thumbnailer لملفات الصوت..."
  sudo tee /usr/share/thumbnailers/audio-thumbnailer.thumbnailer > /dev/null <<EOF
[Thumbnailer Entry]
TryExec=ffmpegthumbnailer
Exec=ffmpegthumbnailer -i %u -o %o -s %s
MimeType=audio/mpeg;audio/mp3;audio/x-mp3;audio/x-mpeg;audio/flac;audio/x-wav;
EOF

  echo "🧹 تنظيف الكاش..."
  rm -rf ~/.cache/thumbnails/*

  echo "🔁 إعادة تشغيل Nautilus..."
  command -v nautilus &>/dev/null && nautilus -q || true
else
  echo "ℹ️ البيئة ليست GNOME، تخطى إصلاح الثامبنيلز."
fi

### 7. تثبيت fastfetch
if ! command -v fastfetch &>/dev/null; then
  echo "📥 تثبيت fastfetch..."
  sudo dnf install -y fastfetch
else
  echo "✅ fastfetch مثبت بالفعل."
fi

### 8. تحميل وتثبيت bauh (AppImage) على XFCE أو LXQt فقط
if [[ "$DESKTOP_ENV" == *"xfce"* || "$DESKTOP_ENV" == *"lxqt"* ]]; then
  echo "🧩 البيئة XFCE أو LXQt: تثبيت bauh..."

  INSTALL_DIR="$HOME/.local/bin"
  DESKTOP_FILE="$HOME/.local/share/applications/bauh.desktop"
  ICON_NAME="system-software-install"

  mkdir -p "$INSTALL_DIR" "$(dirname "$DESKTOP_FILE")"

  echo "📦 تحميل أحدث إصدار من bauh..."
  LATEST_VERSION=$(curl -s https://api.github.com/repos/vinifmor/bauh/releases/latest | grep tag_name | cut -d '"' -f 4)
  FILENAME="bauh-${LATEST_VERSION#v}-x86_64.AppImage"
  DOWNLOAD_URL="https://github.com/vinifmor/bauh/releases/download/${LATEST_VERSION}/${FILENAME}"

  echo "🔗 التحميل من: $DOWNLOAD_URL"
  wget -q --show-progress "$DOWNLOAD_URL" -O "$INSTALL_DIR/bauh.AppImage"
  chmod +x "$INSTALL_DIR/bauh.AppImage"

  echo "📁 إنشاء launcher فى قائمة البرامج..."
  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=bauh
Comment=Manage Flatpak, AppImage, AUR and more
Exec=$INSTALL_DIR/bauh.AppImage
Icon=$ICON_NAME
Terminal=false
Type=Application
Categories=System;PackageManager;
EOF

  update-desktop-database ~/.local/share/applications 2>/dev/null || true

  echo "✅ تم تثبيت bauh بنجاح."
else
  echo "⏭️ البيئة ليست XFCE أو LXQt، تم تخطي bauh."
fi

### 9. سؤال عن إعادة التشغيل
read -p "🔁 هل تريد إعادة تشغيل الجهاز الآن؟ [y/N]: " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
  echo "🔄 جارِ إعادة التشغيل..."
  sleep 3
  sudo reboot
else
  echo "⏭️ تم تخطى إعادة التشغيل."
fi
