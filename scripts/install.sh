#!/usr/bin/env bash
set -e
set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Dieuwe's Dotfiles Installer ==="

echo "Installing packages first..."
"$SCRIPT_DIR/setup-packages.sh"

if [ ! -L "$HOME/.local/share/chezmoi" ]; then
    if [ -d "$HOME/.local/share/chezmoi" ]; then
        echo "Moving existing chezmoi to ~/.local/share/chezmoi.bk..."
        mv "$HOME/.local/share/chezmoi" "$HOME/.local/share/chezmoi.bk"
    fi
    echo "Linking dotfiles via chezmoi..."
    ln -s "$DOTFILES_DIR/chezmoi" "$HOME/.local/share/chezmoi"
else
    echo "Chezmoi already linked."
fi

if command -v chezmoi &> /dev/null; then
    echo "Applying chezmoi..."
    chezmoi apply
else
    echo "Warning: chezmoi not installed, skipped dotfiles setup"
fi

if [ ! -L "$HOME/.emacs.d" ]; then
    if [ -d "$HOME/.emacs.d" ]; then
        echo "Moving existing emacs.d to ~/.emacs.d.bk..."
        mv "$HOME/.emacs.d" "$HOME/.emacs.d.bk"
    fi
    echo "Linking emacs config..."
    ln -s "$DOTFILES_DIR/emacs" "$HOME/.emacs.d"
else
    echo "Emacs config already linked."
fi

HOSTNAME=$(hostname)

if [ "$HOSTNAME" = "kingfisher" ]; then
    echo "Detected Kingfisher machine, running setup-kingfisher.sh..."
    "$SCRIPT_DIR/setup-kingfisher.sh"
fi

echo "=== Installation complete ==="
