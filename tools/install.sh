#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

echo "=== Installing/updating commandline tools ==="

### Composer ###
# @todo check if php exists or a simple self-update is required
echo "Installing Composer!"
wget -qO- https://raw.githubusercontent.com/composer/getcomposer.org/76a7060ccb93902cd7576b67264ad91c8a2700e2/web/installer | php -- --quiet
chmod 0755 composer.phar
mv composer.phar composer
composer --version
#ln -s "$SCRIPT_DIR"/composer ~/bin/composer
### END composer ###

### NVM (Node Version Manager) ###
# [echoes its own install/update messages]
wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.38.0/install.sh | bash
### END nvm ###

### Yarn ###
# [echos its own install/update messages]
wget -qO- https://yarnpkg.com/install.sh | bash
### END yarn ###

### ack (beyond grep) ###
echo "Installing ack!"
wget -qO- https://beyondgrep.com/ack-v3.5.0 > ack
chmod 0755 ack
#ln -s "$SCRIPT_DIR"/ack ~/bin/ack
### END ack ###

echo "=== Commandline tools installed/updated ==="
