# Requirements

Install:

```sh
sudo apt install ansible-core
```

# Deploy

When direnv is not available:

```sh
. .envrc
```

Then install:

```sh
ansible-playbook --ask-become-pass setup.yml
```
