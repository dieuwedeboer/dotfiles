# cachyos defaults (todo - only take what I want from here or write a summary of features)
source /usr/share/cachyos-fish-config/cachyos-config.fish

# introduction (todo - still run fastfetch on first start up)
function fish_greeting
    echo $(randverse) | sed -E 's/  +/:/g'
end

# local bin
#fish_add_path ~/.local/bin

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

