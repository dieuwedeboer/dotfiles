# Dieuwe's Dotfiles

More than just dotfiles - repeatable system setups.

Useful environment configuration for various applications.

## Installation

See ansible directory for new steps.

These are legacy instructions:

```
git clone git@github.com:dieuwedeboer/dotfiles.git ~/.dotfiles
~/.dotfiles/install.sh
```
## TODO

* Finish shift to ansible with variable docroot (`~/src` is hardcoded).
* Tweak fish to show directory and git remotes.
* Use chezmoi for dotfiles (so remove them from ansible)
* Eglot (PHP/TS) and Aidermacs out-of-the-box.
* Keep `.emacs.d` clean and re-theme for terminal.
* Install/update lando.
* Include GNOME top bar config.

## Further inspiration

I want to go through a lot of David Wilson's (System Crafters) Emacs
config for more gems and other productivity tools that I will find
useful: https://github.com/daviwil/dotfiles/blob/master/Emacs.org
