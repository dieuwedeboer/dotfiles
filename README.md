# Dieuwe's Dotfiles

In the process of a rewrite for Arch (CachyOS).

More than just dotfiles - repeatable system setups.

Useful environment configuration for various applications.

Alacrity with fish and zellij form the basis for a full in-terminal development
experience.

## Installation

```
git clone git@github.com:dieuwedeboer/dotfiles.git
ln -s ~/dotfiles/chezmoi ~/.local/share/chezmoi
cd ~/dotfiles/ansible/workstation
cat README.md
```

Ansible will build Emacs, setup the terminal environemt, and run
`chezmoi apply` to put all the dotfiles in place.

## Todo

* Tutorial on how to set up based install: ZFS native encryption with CachyOS
* Init to set up all packages using pacman (and a few from aur/flathub)
* Keep `.emacs.d` clean.
* Install composer and drupalorg plus drupal-check global.
* Install/update lando.
* Improve emacs, nvim, and zellij themes to my liking.
* Include Plasma and Hyprland configs.

## Further inspiration

I want to go through a lot of David Wilson's (System Crafters) Emacs
config for more gems and other productivity tools that I will find
useful: https://github.com/daviwil/dotfiles/blob/master/Emacs.org
