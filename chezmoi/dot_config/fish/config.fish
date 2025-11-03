# introduction
function fish_greeting
  echo $(randverse) | sed -E 's/  +/:/g'
end

# install fundle
if not functions -q fundle; eval (curl -sfL https://git.io/fundle-install); end
fundle plugin 'danhper/fish-ssh-agent'
fundle init

# make sure .local/bin is in path
fish_add_path ~/.local/bin

# indispensable aliases (prefer abbreviations)
alias vi vim
abbr e 'emacsclient -nw'
abbr z 'zellij'
abbr drush 'lando drush'
abbr t 'tmuxinator start main'
abbr texit 'tmuxinator stop main'
# fix common misspellings
abbr got git

# better prompt
starship init fish | source

# direnv
direnv hook fish | source

# start tmux immediately
#if status is-interactive
#    and not set -q TMUX
#    if not test -e ~/.emacs.d/.emacs.desktop.lock
#	tmux has-session -t main 2> /dev/null
#	if [ $status -ne 0 ]
#	    exec tmuxinator start main
#	else
#	    echo "tmux session already running; to return to it, type: tmuxinator start main"
#	end
#    else
#	echo Emacs lock file exists, will not start tmux. >&2
#    end
#end

# lando
fish_add_path ~/.lando/bin

# composer global
fish_add_path ~/.config/composer/vendor/bin

# local exports and overrides
source ~/.config/fish/local.fish
