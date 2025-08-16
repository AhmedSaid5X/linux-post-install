#!/bin/bash

# ==========================================================
#  Zsh + Oh My Zsh + Plugins + Starship + Nerd Font Installer
# ==========================================================

set -e

# Detect package manager
if command -v dnf &>/dev/null; then
    PKG_INSTALL="sudo dnf install -y"
elif command -v pacman &>/dev/null; then
    PKG_INSTALL="sudo pacman -S --noconfirm"
elif command -v apt &>/dev/null; then
    PKG_INSTALL="sudo apt install -y"
else
    echo "❌ Unsupported package manager"
    exit 1
fi

echo "🚀 Installing Zsh, curl, git..."
$PKG_INSTALL zsh curl git unzip

echo "🎨 Installing Nerd Font (JetBrains Mono)..."
if [[ "$PKG_INSTALL" == *"dnf"* ]]; then
    $PKG_INSTALL jetbrains-mono-fonts-all
elif [[ "$PKG_INSTALL" == *"pacman"* ]]; then
    $PKG_INSTALL ttf-jetbrains-mono-nerd
else
    mkdir -p ~/.local/share/fonts
    curl -LO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
    unzip JetBrainsMono.zip -d ~/.local/share/fonts
    fc-cache -fv
fi

echo "💾 Setting Zsh as default shell..."
chsh -s "$(which zsh)"

echo "📦 Installing Oh My Zsh..."
RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

echo "🔌 Installing Zsh plugins..."
ZSH_CUSTOM=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM}/plugins/zsh-completions

echo "✨ Installing Starship prompt..."
curl -sS https://starship.rs/install.sh | sh -s -- -y

echo "⚙️ Configuring Zsh..."
# Add all plugins and Starship to .zshrc
sed -i 's/^plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions)/' ~/.zshrc
echo 'eval "$(starship init zsh)"' >> ~/.zshrc

echo "✅ Done! Restart your terminal and select 'JetBrainsMono Nerd Font' in terminal settings."
