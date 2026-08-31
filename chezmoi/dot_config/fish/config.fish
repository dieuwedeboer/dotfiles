# cachyos defaults (todo - only take what I want from here or write a summary of features)
source /usr/share/cachyos-fish-config/cachyos-config.fish

# hello there
function fish_greeting
    if not set -q ZELLIJ
        fastfetch
    else
        echo $(randverse) | sed -E 's/  +/:/g'
    end
end

# aliases (discouraged - not transparent)
alias vi nvim

# abbreviations (encouraged)
abbr e 'emacsclient -nw'
abbr z 'zellij'
abbr drush 'ddev drush'

# fix common misspellings
abbr got git

# better prompt
starship init fish | source

# direnv
direnv hook fish | source

# composer
fish_add_path ~/.config/composer/vendor/bin

# local exports and overrides
# MONARCHY_FONT_PT_OFFSET belongs in ~/.config/environment.d/monarchy-font.conf,
# not here: emacs.service and omarchy hooks never see fish local.
source ~/.config/fish/local.fish
