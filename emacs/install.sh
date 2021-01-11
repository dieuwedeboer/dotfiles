#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

echo "=== Installing new Emacs configuration ==="

# @todo Replace this with a check and a warning rather forcing install
sudo apt install emacs

if [ -h ~/.emacs.d ]; then
    # Remove if existing symlink
    rm ~/.emacs.d
elif [ -d ~/.emacs.d ]; then
    # Backup if existing directory
    # @todo Do this to the dotfiles/backup dir with a timestamp
    mv ~/.emacs.d ~/.emacs.d.bak
fi

ln -s "$SCRIPT_DIR" ~/.emacs.d
