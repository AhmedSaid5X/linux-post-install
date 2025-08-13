#!/bin/bash
set -e

echo "🚀 بدء التثبيت الكامل لما بعد تثبيت Arch Linux..."

# سؤال للمستخدم يختار نوع التثبيت
echo "اختر نوع التثبيت:"
echo "1) تثبيت كامل (Performance + Security + Services)"
echo "2) تثبيت خفيف (Essential packages only)"
read -rp "اختيارك (1/2): " choice

### 1. تحديث النظام وإضافة Flathub ###
sudo pacman -Syu --needed --noconfirm flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

### 2. تثبيت الحزم الأساسية ###
sudo pacman -S --needed --noconfirm \
  git base-devel pacman-contrib \
  noto-fonts noto-fonts-emoji noto-fonts-extra \
  ttf-dejavu ttf-liberation ttf-scheherazade-new \
  mpv mkvtoolnix-gui firefox qbittorrent \
  power-profiles-daemon ufw gamemode lib32-gamemode \
  xdg-user-dirs networkmanager ntp apparmor

# لو اختار تثبيت كامل نضيف باقي الخدمات
if [[ "$choice" == "1" ]]; then
  sudo pacman -S --needed --noconfirm \
    systemd-oomd thermald preload fail2ban
fi

### 3. تفعيل الخدمات ###
# خدمات أساسية
sudo ufw enable
sudo systemctl enable ufw
sudo systemctl enable --now power-profiles-daemon
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now apparmor
sudo systemctl enable --now fstrim.timer
sudo timedatectl set-ntp true
sudo usermod -aG gamemode "$USER"
xdg-user-dirs-update

# لو تثبيت كامل نفعّل الخدمات الإضافية
if [[ "$choice" == "1" ]]; then
  sudo systemctl enable --now thermald
  sudo systemctl enable --now systemd-oomd
  sudo systemctl enable --now fail2ban
  sudo systemctl enable --now paccache.timer
fi

### 4. تحسين إعدادات pacman ###
sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
sudo sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 5/' /etc/pacman.conf
grep -q '^ILoveCandy' /etc/pacman.conf || echo "ILoveCandy" | sudo tee -a /etc/pacman.conf

### 5. تثبيت yay لو مش موجود ###
if ! command -v yay &>/dev/null; then
  tmpdir=$(mktemp -d)
  git clone https://aur.archlinux.org/yay-bin.git "$tmpdir"
  cd "$tmpdir"
  makepkg -si --noconfirm
  cd -
  rm -rf "$tmpdir"
fi

### 6. تثبيت حزم من AUR ###
yay -S --needed --noconfirm \
  ttf-amiri ttf-sil-harmattan ffmpegthumbs-git autosubsync-bin

### 7. التنظيف ###
sudo paccache -r
sudo pacman -Rns --noconfirm $(pacman -Qtdq || true)
yay -Sc --noconfirm
sudo journalctl --vacuum-time=7d
flatpak uninstall --unused -y

echo "✨ تم التثبيت بنجاح! 🚀"
