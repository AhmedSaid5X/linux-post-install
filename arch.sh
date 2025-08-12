#!/bin/bash
set -e

### دالة تثبيت yay ###
install_yay() {
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
}

### دالة تثبيت Flatpak ###
install_flatpak() {
  if ! command -v flatpak &>/dev/null; then
    echo "🛠️ تثبيت flatpak..."
    sudo pacman -S --needed --noconfirm flatpak
  fi
}

### دالة إضافة Flathub ###
add_flathub_repo() {
  if ! flatpak remote-list | grep -q "^flathub$"; then
    echo "🌐 إضافة مستودع Flathub..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  fi
}

### دالة التثبيت ###
install_all() {
  echo "🚀 بدء تثبيت كل البرامج والخطوط المطلوبة..."
  install_yay

  sudo pacman -Syu --needed --noconfirm \
    noto-fonts noto-fonts-emoji noto-fonts-extra \
    ttf-dejavu ttf-liberation ttf-scheherazade-new \
    mpv mkvtoolnix-gui firefox

  yay -S --needed --noconfirm \
    ttf-amiri ttf-sil-harmattan ffmpegthumbs-git

  install_flatpak
  add_flathub_repo
}

### دالة التنظيف ###
clean_system() {
  echo "🧹 بدء تنظيف النظام..."

  # pacman-contrib
  if ! command -v paccache &>/dev/null; then
      echo "🛠️ تثبيت pacman-contrib..."
      sudo pacman -S --noconfirm pacman-contrib
  fi

  echo "🗑️ تنظيف كاش pacman..."
  sudo paccache -r

  echo "🧹 حذف الحزم اليتيمة..."
  orphans=$(pacman -Qtdq || true)
  if [[ -n "$orphans" ]]; then
      sudo pacman -Rns --noconfirm $orphans
  else
      echo "✅ مفيش حزم يتييمة."
  fi

  if command -v yay &>/dev/null; then
      echo "🗑️ تنظيف كاش AUR..."
      yay -Sc --noconfirm
  fi

  echo "🗄️ تنظيف الـ logs..."
  sudo journalctl --vacuum-time=7d

  if command -v flatpak &>/dev/null; then
      echo "📦 تنظيف flatpak..."
      flatpak uninstall --unused -y
  fi

  if command -v snap &>/dev/null; then
      echo "📦 تنظيف snap..."
      sudo snap set system refresh.retain=2
      sudo snap remove --purge $(snap list --all | awk '/disabled/{print $1, $2}')
  fi

  echo "✨ تم تنظيف النظام بنجاح!"
}

### تشغيل كل الخطوات ###
install_all
clean_system

echo "🚀 تم التثبيت والتنظيف بنجاح!"
