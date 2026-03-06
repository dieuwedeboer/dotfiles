#!/usr/bin/env bash
set -e
set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Dieuwe's Dotfiles Installer ==="

if ! command -v chezmoi &> /dev/null; then
    echo "Installing chezmoi..."
    curl -sfL https://get.chezmoi.io | sh -s -- -b ~/.local/bin
    export PATH="$HOME/.local/bin:$PATH"
fi

if [ ! -L "$HOME/.local/share/chezmoi" ]; then
    if [ -d "$HOME/.local/share/chezmoi" ]; then
        echo "Warning: ~/.local/share/chezmoi exists and is not a symlink. Skipping."
    else
        echo "Linking dotfiles via chezmoi..."
        ln -s "$DOTFILES_DIR/chezmoi" "$HOME/.local/share/chezmoi"
    fi
else
    echo "Chezmoi already linked."
fi

if [ ! -L "$HOME/.emacs.d" ]; then
    if [ -d "$HOME/.emacs.d" ]; then
        echo "Warning: ~/.emacs.d exists and is not a symlink. Skipping."
    else
        echo "Linking emacs config..."
        ln -s "$DOTFILES_DIR/emacs" "$HOME/.emacs.d"
    fi
else
    echo "Emacs config already linked."
fi

echo "Running setup-packages.sh..."
"$SCRIPT_DIR/setup-packages.sh"

echo "Applying chezmoi..."
chezmoi apply

HOSTNAME=$(hostname)

if [ "$HOSTNAME" = "kingfisher" ]; then
    echo "Detected Kingfisher machine, running setup-kingfisher.sh..."
    "$SCRIPT_DIR/setup-kingfisher.sh"
fi

echo "=== Installation complete ==="
