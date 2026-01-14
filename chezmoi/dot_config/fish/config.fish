# cachyos defaults (todo - only take what I want from here or write a summary of features)
source /usr/share/cachyos-fish-config/cachyos-config.fish

# hello there
function fish_greeting
    if not set -q FASTFETCH_GREETING
        fastfetch
        set -U FASTFETCH_GREETING 1
    else
        echo $(randverse) | sed -E 's/  +/:/g'
    end
end

# aliases (discouraged - not transparent)
alias vi nvim

# abbreviations (encouraged)
abbr e 'emacsclient -nw'
abbr z 'zellij'
abbr drush 'lando drush'

# fix common misspellings
abbr got git

# better prompt
starship init fish | source

# direnv
direnv hook fish | source

# opencode
fish_add_path ~/.opencode/bin

# lando
fish_add_path ~/.lando/bin

# composer
fish_add_path ~/.config/composer/vendor/bin

# local exports and overrides
source ~/.config/fish/local.fish
