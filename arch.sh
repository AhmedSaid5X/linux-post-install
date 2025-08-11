#!/bin/bash
set -e

# تأكد من وجود yay (AUR helper)
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

# تأكد من وجود flatpak
install_flatpak() {
  if ! command -v flatpak &>/dev/null; then
    echo "🛠️ تثبيت flatpak..."
    sudo pacman -S --needed --noconfirm flatpak
  fi
}

# إضافة مستودع Flathub لو مش مضاف
add_flathub_repo() {
  if ! flatpak remote-list | grep -q "^flathub$"; then
    echo "🌐 إضافة مستودع Flathub..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  fi
}

# تحقق إذا الحزمة موجودة في pacman repo
pacman_has_package() {
  pacman -Ss "^$1$" | grep -q "^community/$1\|^extra/$1\|^core/$1\|^multilib/$1"
}

# تحقق إذا الحزمة موجودة في AUR
aur_has_package() {
  yay -Ss "^$1$" | grep -q "^aur/$1"
}

# تحقق إذا الحزمة موجودة كـ flatpak
flatpak_has_package() {
  flatpak remote-ls flathub | grep -q "$1"
}

# تثبيت برنامج بالترتيب: pacman -> yay -> flatpak
install_package() {
  local pkg="$1"
  local flatpak_ref="$2"

  echo "🔍 محاولة تثبيت $pkg ..."

  if pacman_has_package "$pkg"; then
    echo "🖥️ تثبيت $pkg من المستودعات الرسمية (pacman)..."
    sudo pacman -S --needed --noconfirm "$pkg"
  else
    install_yay
    if aur_has_package "$pkg"; then
      echo "📦 تثبيت $pkg من AUR (yay)..."
      yay -S --needed --noconfirm "$pkg"
    else
      if [[ -n "$flatpak_ref" ]]; then
        install_flatpak
        add_flathub_repo
        if flatpak_has_package "$flatpak_ref"; then
          echo "📦 تثبيت $pkg من Flatpak ($flatpak_ref)..."
          flatpak install -y flathub "$flatpak_ref"
        else
          echo "⚠️ لم أجد $flatpak_ref في Flathub."
        fi
      else
        echo "⚠️ لم أجد $pkg في المستودعات الرسمية، ولا في AUR، ولا Flatpak."
      fi
    fi
  fi
}

# تثبيت الخطوط
echo "🚀 تثبيت الخطوط..."
sudo pacman -S --needed --noconfirm noto-fonts noto-fonts-emoji noto-fonts-extra ttf-dejavu ttf-liberation ttf-scheherazade-new
install_yay
yay -S --needed --noconfirm ttf-amiri ttf-sil-harmattan

# قائمة البرامج مع flatpak refs لو موجود
declare -A packages=(
  [fastfetch]=""
  [flatpak]=""
  [mpv]=""
  [telegram-desktop]="org.telegram.desktop"
  [discord]="com.discordapp.Discord"
  [mkvtoolnix-cli]=""
  [qbittorrent]="org.qbittorrent.qBittorrent"
  [spotify]="com.spotify.Client"
  [subtitlecomposer]=""
  [upscayl]=""
  [podman-desktop]=""
  [curl]=""
  [flatseal]="com.github.tchx84.Flatseal"
  [jellyfin-media-player]=""
  [jellyfin-mpv-shim]=""
  [warehouse-bin]=""
  [mission-center-bin]=""
)

echo "🚀 تثبيت البرامج..."

for pkg in "${!packages[@]}"; do
  install_package "$pkg" "${packages[$pkg]}"
done

echo "✅ انتهى التثبيت. اضغط Enter للخروج..."
read -r
