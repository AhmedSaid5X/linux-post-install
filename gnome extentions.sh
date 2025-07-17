#!/bin/bash

echo "🚀 فتح Extension Manager GUI لتثبيت الإضافات المطلوبة..."

# تأكد إن extension-manager متثبت
if ! command -v extension-manager &> /dev/null; then
  echo "📦 جاري تثبيت Extension Manager..."
  flatpak install -y flathub com.mattjakeman.ExtensionManager
fi

# فتح Extension Manager
flatpak run com.mattjakeman.ExtensionManager &

sleep 2

echo "🧩 من فضلك ابحث عن الإضافات التالية وثبتها يدويًا من البرنامج:"

echo "1️⃣ AppIndicator and KStatusNotifierItem Support"
echo "2️⃣ Blur My Shell"
echo "3️⃣ GNOME Fuzzy App Search"

echo "✅ بعد التثبيت، فعلهم و اعمل logout أو restart لو احتاج."


