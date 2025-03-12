# install fundle
if not functions -q fundle; eval (curl -sfL https://git.io/fundle-install); end
fundle plugin 'danhper/fish-ssh-agent'
fundle init

# make sure .local/bin is in path
set PATH $PATH ~/.local/bin

# indispensable aliases
alias vi vim # use vim
alias e="emacsclient -nw"

# better prompt
starship init fish | source

# access go installs
set PATH $PATH ~/go/bin

# switch to default node
nvm use default

# direnv
# [workstation variable exports and keys load from ~/.envrc]
direnv hook fish | source

# start tmux immediately
if status is-interactive
    and not set -q TMUX
    if not test -e ~/.emacs.d/.emacs.desktop.lock
	tmux has-session -t main 2> /dev/null
	if [ $status -ne 0 ]
	    exec tmuxinator start main
	else
	    echo "tmux session already running; to return to it, type: tmuxinator start main"
	end
    else
	echo Emacs lock file exists, will not start tmux. >&2
    end
end

# lando
export PATH="/home/dieuwe/.lando/bin:$PATH";
