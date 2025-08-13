#!/bin/bash
set -euo pipefail

# =========================
# Arch Post Install Pro (Bash) - Full Auto with AUR Fail-Safe (Fixed)
# =========================

# ---- Config ----
AUR_TIMEOUT=${AUR_TIMEOUT:-180}
YAY_MAKE_TIMEOUT=${YAY_MAKE_TIMEOUT:-300}
FLATPAK_TIMEOUT=${FLATPAK_TIMEOUT:-180}
REFLECTOR_TIMEOUT=${REFLECTOR_TIMEOUT:-60}

# ---- Logging & UI ----
START_TIME=$(date +'%F %T')
LOG_FILE="$HOME/arch-post-install-$(date +'%Y%m%d-%H%M%S').log"
MISSING_PKGS_FILE="$HOME/missing-packages.log"
MISSING_SERVICES_FILE="$HOME/missing-services.log"
: > "$MISSING_PKGS_FILE"
: > "$MISSING_SERVICES_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

step() { echo -e "\n\033[1;36m[$(date +'%H:%M:%S')] ➤ $*\033[0m"; }
ok()   { echo -e "\033[1;32m✔ $*\033[0m"; }
warn() { echo -e "\033[1;33m⚠ $*\033[0m"; }
err()  { echo -e "\033[1;31m✖ $*\033[0m"; }

trap 'err "حصل خطأ! راجع اللوج: $LOG_FILE"' ERR

# ---- Helpers ----
with_timeout() {
  local seconds="$1"; shift
  if ! timeout "$seconds" "$@"; then
    return 124
  fi
}

enable_now_if_exists() {
  local unit="$1"
  if systemctl list-unit-files | awk '{print $1}' | grep -qx "$unit"; then
    if ! systemctl is-enabled --quiet "$unit"; then
      sudo systemctl enable --now "$unit"
      ok "تم تفعيل الخدمة: $unit"
    else
      ok "الخدمة مفعّلة بالفعل: $unit"
    fi
  else
    warn "الخدمة مش موجودة: $unit"
    echo "$unit" >> "$MISSING_SERVICES_FILE"
  fi
}

safe_rm_if_exists() {
  shopt -s nullglob
  local arr=( $1 )
  if (( ${#arr[@]} )); then
    rm -rf "${arr[@]}"
  fi
  shopt -u nullglob
}

require_internet() {
  step "فحص الاتصال بالإنترنت"
  if ping -c 1 -W 3 archlinux.org &>/dev/null; then
    ok "الإنترنت شغال."
  else
    err "مفيش اتصال بالإنترنت."
  fi
}

require_sudo() {
  step "فحص صلاحيات sudo"
  if sudo -n true 2>/dev/null; then
    ok "صلاحيات sudo جاهزة."
  else
    warn "السكربت هيطلب باسورد sudo عند الحاجة."
  fi
}

# ---- Pacman helpers ----
install_pacman_checked() {
  local pkgs=("$@")
  local avail=()
  for pkg in "${pkgs[@]}"; do
    if pacman -Si "$pkg" &>/dev/null; then
      avail+=("$pkg")
    else
      warn "الحزمة مش موجودة في مستودعات pacman: $pkg"
      echo "$pkg" >> "$MISSING_PKGS_FILE"
    fi
  done
  if (( ${#avail[@]} )); then
    sudo pacman -S --noconfirm --needed -q "${avail[@]}"
  else
    warn "مفيش ولا حزمة صالحة للتثبيت من pacman فى البلوك ده."
  fi
}

# ---- AUR helpers ----
ensure_yay() {
  if command -v yay &>/dev/null; then
    ok "yay موجود بالفعل"
    return 0
  fi
  step "تثبيت yay (AUR)"
  sudo pacman -S --needed --noconfirm base-devel git || true
  local tmpdir
  tmpdir=$(mktemp -d)
  if with_timeout "$YAY_MAKE_TIMEOUT" git clone https://aur.archlinux.org/yay-bin.git "$tmpdir/yay-bin"; then
    pushd "$tmpdir/yay-bin" >/dev/null
    if with_timeout "$YAY_MAKE_TIMEOUT" makepkg -si --noconfirm; then
      ok "تم تثبيت yay"
    else
      warn "فشل makepkg لتثبيت yay خلال المهلة. هنتخطى خطوات AUR."
    fi
    popd >/dev/null || true
  else
    warn "فشل git clone من AUR خلال المهلة. هنتخطى خطوات AUR."
  fi
  rm -rf "$tmpdir"
}

install_aur_failsafe() {
  local pkgs=("$@")
  if ! command -v yay &>/dev/null; then
    warn "yay مش متاح؛ تخطى كل حزم AUR: ${pkgs[*]}"
    for p in "${pkgs[@]}"; do echo "$p" >> "$MISSING_PKGS_FILE"; done
    return 0
  fi
  for pkg in "${pkgs[@]}"; do
    step "تثبيت من AUR: $pkg"
    if with_timeout "$AUR_TIMEOUT" yay -S --needed --noconfirm --removemake \
        --answerdiff None --answeredit None --noredownload "$pkg"; then
      ok "تم تثبيت $pkg (AUR)"
    else
      warn "فشل تثبيت $pkg من AUR (مهلة/خطأ). تم تخطيه."
      echo "$pkg" >> "$MISSING_PKGS_FILE"
    fi
  done
}

# ========================= تنفيذ =========================
require_internet
require_sudo

# 1) تحديث النظام + Flathub
step "تحديث النظام وإضافة Flathub"
install_pacman_checked flatpak
sudo pacman -Syu --noconfirm || true
if ! with_timeout "$FLATPAK_TIMEOUT" flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; then
  warn "تخطى إضافة Flathub بسبب المهلة."
fi
with_timeout "$FLATPAK_TIMEOUT" flatpak update --appstream -y || true
ok "تم."

# 1.1) تثبيت برامج Flatpak
step "تثبيت برامج Flatpak"
with_timeout "$FLATPAK_TIMEOUT" flatpak install -y flathub \
  com.github.iwalton3.jellyfin-mpv-shim \
  com.github.tchx84.Flatseal || warn "تخطى بعض تطبيقات Flatpak بسبب مهلة/خطأ"
ok "تم تثبيت برامج Flatpak."

# 2) اختيار أسرع مرايا
step "تثبيت reflector وتحديث قائمة المرايا"
install_pacman_checked reflector
if ! with_timeout "$REFLECTOR_TIMEOUT" sudo reflector --country "Egypt","Germany","Netherlands" --protocol https \
  --latest 20 --sort rate --score 10 --save /etc/pacman.d/mirrorlist; then
  warn "reflector فشل فى كتابة mirrorlist (مهلة/شبكة)"
fi
sudo pacman -Syy || true
ok "تم تحديث /etc/pacman.d/mirrorlist"

# 3) الحزم الأساسية
step "تثبيت الحزم الأساسية (pacman)"
install_pacman_checked \
  archlinux-keyring \
  git base-devel pacman-contrib reflector \
  noto-fonts noto-fonts-emoji noto-fonts-extra \
  ttf-dejavu ttf-liberation ttf-scheherazade-new \
  mpv mkvtoolnix-gui firefox qbittorrent \
  power-profiles-daemon ufw gamemode lib32-gamemode \
  xdg-user-dirs networkmanager ntp apparmor \
  thermald fail2ban
ok "تم تثبيت الحزم."

# 4) تحسين pacman
step "تحسين pacman"
sudo sed -i 's/^#Color/Color/' /etc/pacman.conf || true
if grep -q '^#ParallelDownloads' /etc/pacman.conf; then
  sudo sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
elif ! grep -q '^ParallelDownloads' /etc/pacman.conf; then
  echo "ParallelDownloads = 5" | sudo tee -a /etc/pacman.conf >/dev/null
fi
if ! grep -q '^ILoveCandy' /etc/pacman.conf; then
  sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
fi
ok "تم."

# 5) تفعيل الخدمات
step "تفعيل الخدمات الأساسية"
SERVICES=(
  ufw.service
  power-profiles-daemon.service
  NetworkManager.service
  apparmor.service
  fstrim.timer
  thermald.service
  systemd-oomd.service
  fail2ban.service
  paccache.timer
)
for svc in "${SERVICES[@]}"; do
  enable_now_if_exists "$svc"
done
sudo ufw enable || true
sudo timedatectl set-ntp true || true

if ! id -nG "$USER" | grep -qw gamemode; then
  sudo usermod -aG gamemode "$USER" || true
  ok "تم إضافة $USER لمجموعة gamemode (سجّل خروج/دخول)."
else
  ok "مجموعة gamemode مضافة بالفعل."
fi
xdg-user-dirs-update || true

# 6) zram
step "تهيئة zram"
install_pacman_checked zram-generator
ZCONF="/etc/systemd/zram-generator.conf"
if [[ ! -f "$ZCONF" ]]; then
  sudo tee "$ZCONF" >/dev/null <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF
  sudo systemctl daemon-reload
  warn "zram هيتفعل بعد إعادة التشغيل."
else
  ok "ملف zram-generator.conf موجود بالفعل"
fi

# 7) sysctl
step "ضبط sysctl"
SYSCTL="/etc/sysctl.d/99-tuned.conf"
sudo tee "$SYSCTL" >/dev/null <<'EOF'
vm.swappiness = 10
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
vm.vfs_cache_pressure = 75
EOF
sudo sysctl --system >/dev/null 2>&1 || sudo sysctl --system >/dev/null
ok "تم تطبيق إعدادات sysctl"

# 8) yay
ensure_yay

# 9) AUR
step "تثبيت حزم من AUR"
install_aur_failsafe \
  ttf-amiri ttf-sil-harmattan ffmpegthumbs-git autosubsync-bin
ok "انتهى قسم AUR."

# 10) مؤقّت التحديثات
step "إعداد مؤقّت لفحص التحديثات"
sudo tee /etc/systemd/system/arch-checkupdates.service >/dev/null <<'EOF'
[Unit]
Description=Arch checkupdates logger

[Service]
Type=oneshot
ExecStart=/bin/bash -c '/usr/bin/checkupdates || true'
StandardOutput=append:/var/log/arch-updates.log
StandardError=append:/var/log/arch-updates.log
EOF

sudo tee /etc/systemd/system/arch-checkupdates.timer >/dev/null <<'EOF'
[Unit]
Description=Run arch-checkupdates daily

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=900

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
enable_now_if_exists arch-checkupdates.timer
ok "تم."

# 11) تنظيف
step "تنظيف النظام"
sudo paccache -r || true
sudo pacman -Rns --noconfirm $(pacman -Qtdq || true) || true
yay -Sc --noconfirm || true
sudo journalctl --vacuum-time=7d || true
with_timeout "$FLATPAK_TIMEOUT" flatpak uninstall --unused -y || true
sudo pacman -Sc --noconfirm || true

safe_rm_if_exists "$HOME/.cache/"*
safe_rm_if_exists "$HOME/.npm/"*
safe_rm_if_exists "$HOME/.cargo/registry"*
safe_rm_if_exists "$HOME/.cargo/git"*

ok "تم التنظيف."

# Summary
END_TIME=$(date +'%F %T')
echo
ok "✨ خلصنا! بدأ: $START_TIME — انتهى: $END_TIME"
echo "📄 ملف اللوج: $LOG_FILE"
[[ -s "$MISSING_PKGS_FILE" ]] && warn "📦 حزم مفقودة: $MISSING_PKGS_FILE"
[[ -s "$MISSING_SERVICES_FILE" ]] && warn "🧩 خدمات مفقودة: $MISSING_SERVICES_FILE"
echo "💡 ملاحظات:"
echo "- يفضل إعادة التشغيل علشان zram يشتغل."
echo "- gamemode يتفعل بعد تسجيل الخروج/الدخول."
echo "- سجل التحديثات اليومية: /var/log/arch-updates.log"
