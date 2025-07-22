# Dieuwe's Dotfiles

More than just dotfiles - repeatable system setups.

Useful environment configuration for various applications.

Alacrity with fish and tmux form the basis for a full in-terminal development
experience.

## Installation

```
git clone git@github.com:dieuwedeboer/dotfiles.git ~/src
cd ~/src/ansible/workstation
cat README.md
```

Ansible will build Emacs, setup the terminal environemt, and run
`chezmoi apply` to put all the dotfiles in place.

The use of `~/src` is currently hardcoded in a few places but will be
removed in the future.

## Todo

* Finish shift to ansible with variable docroot (`~/src` is hardcoded).
* Tweak fish to show git remote and add ~/bin to path.
* Keep `.emacs.d` clean.
* Install ack.
* Install/update lando.
* Improve both tmux and emacs themes to my liking.
* Include bits of GNOME config and theme.

## Further inspiration

I want to go through a lot of David Wilson's (System Crafters) Emacs
config for more gems and other productivity tools that I will find
useful: https://github.com/daviwil/dotfiles/blob/master/Emacs.org
