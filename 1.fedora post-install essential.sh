#!/bin/bash

set -e

echo "🚀 بدء تجهيز النظام بعد التثبيت..."

# 1. إضافة RPM Fusion
echo "📦 إضافة RPM Fusion (Free & Non-Free)..."
sudo dnf install -y \
  https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
  https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# 2. دعم Flatpak + Flathub
echo "📦 تثبيت flatpak وإضافة Flathub..."
sudo dnf install -y flatpak

if ! flatpak remote-list | grep -q flathub; then
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  echo "✅ Flathub تمت إضافته."
else
  echo "✅ Flathub موجود بالفعل."
fi

# 3. تحديث النظام
echo "🔄 تحديث النظام بالكامل..."
sudo dnf update -y

# 4. استبدال ffmpeg-free بـ ffmpeg الكامل
echo "🎞️ استبدال ffmpeg-free بـ ffmpeg..."
sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing

# 5. تحديث multimedia group بدون إضافات ضعيفة
echo "🎧 تحديث multimedia group..."
sudo dnf update @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin

# 6. كشف بيئة سطح المكتب الحالية
DESKTOP_ENV=$(echo "${XDG_CURRENT_DESKTOP,,}") # يخليها كلها lowercase

echo "🖥️ بيئة سطح المكتب الحالية: $DESKTOP_ENV"

# 7. تثبيت App Store المناسب حسب البيئة
if [[ "$DESKTOP_ENV" == *"xfce"* ]]; then
  echo "🛍️ Xfce detected: تثبيت gnome-software..."
  sudo dnf install -y gnome-software
elif [[ "$DESKTOP_ENV" == *"lxqt"* ]]; then
  echo "🛍️ LXQt detected: تثبيت plasma-discover..."
  sudo dnf install -y plasma-discover
else
  echo "ℹ️ لم يتم الكشف عن Xfce أو LXQt، تخطى تثبيت App Store."
fi

# 8. إصلاح مشاكل الثامبنيلز في GNOME فقط
if [[ "$DESKTOP_ENV" == *"gnome"* ]]; then
  echo "🔧 GNOME detected: إصلاح مشاكل الثامبنيلز..."
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

  echo "🧹 مسح كاش الثامبنيلز القديم..."
  rm -rf ~/.cache/thumbnails/*

  echo "🔁 إعادة تشغيل Nautilus..."
  command -v nautilus &>/dev/null && nautilus -q || true
else
  echo "ℹ️ بيئة سطح المكتب ليست GNOME، تخطى خطوة إصلاح الثامبنيلز."
fi

# 9. تثبيت fastfetch لو مش موجود
if ! command -v fastfetch &>/dev/null; then
  echo "📥 تثبيت fastfetch..."
  sudo dnf install -y fastfetch
fi

# 10. سؤال المستخدم عن إعادة التشغيل
read -p "🔁 هل تريد إعادة تشغيل الجهاز الآن؟ [y/N]: " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
  echo "🔄 جارِ إعادة تشغيل الجهاز..."
  sleep 3
  sudo reboot
else
  echo "⏭️ تم تخطي إعادة التشغيل."
fi
