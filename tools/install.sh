#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

echo "=== Installing/updating commandline tools ==="

# @todo decide if we should install them in here and then add that
# bin to the path, or if we should modify ~/bin
mkdir -p ~/bin

### Composer ###
# @todo check if php exists or a simple self-update is required
# @todo run install-composer.sh instead of this
echo "Installing Composer!"
wget -qO- https://raw.githubusercontent.com/composer/getcomposer.org/76a7060ccb93902cd7576b67264ad91c8a2700e2/web/installer | php -- --quiet
chmod 0755 composer.phar
mv composer.phar ~/bin/composer
composer --version
#ln -s "$SCRIPT_DIR"/bin/composer ~/bin/composer
### END composer ###

### NVM (Node Version Manager) ###
# [echoes its own install/update messages]
wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.38.0/install.sh | bash
### END nvm ###

### ack (beyond grep) ###
echo "Installing ack!"
wget -qO- https://beyondgrep.com/ack-v3.5.0 > ~/bin/ack
chmod 0755 ~/bin/ack
#ln -s "$SCRIPT_DIR"/bin/ack ~/bin/ack
### END ack ###

source ~/.profile

echo "=== Commandline tools installed/updated ==="
