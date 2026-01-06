#!/usr/bin/env bash

################################################################
# Ansible Repository Set up Script
################################################################
# local users must join the "ansible-admins" group in order to
# work with ansible. (Or they can't access the ansible keypair)
# The service account "ansible" is to be used to access any
# remote hosts
################################################################

set -e

### CONFIGURATION ###
REPO_ROOT="/srv/ansible"
ANSIBLE_USER="ansible"
ANSIBLE_GROUP="ansible-admins"
TARGET="$REPO_ROOT/infrastructure"
#####################

echo "Creating Ansible repo structure at $TARGET"
mkdir -p "$TARGET"
cd "$TARGET"

###############################################################
# 1. Ensure local ansible + ansible-admins group exist
###############################################################

echo "Ensuring $ANSIBLE_GROUP group exists..."
if ! getent group "$ANSIBLE_GROUP" >/dev/null; then
    sudo groupadd "$ANSIBLE_GROUP"
fi

echo "Ensuring $ANSIBLE_USER user exists..."
if ! id "$ANSIBLE_USER" >/dev/null 2>&1; then
    sudo useradd -m -s /bin/bash -G "$ANSIBLE_GROUP" "$ANSIBLE_USER"
else
    # Ensure user is in the group
    sudo usermod -aG "$ANSIBLE_GROUP" "$ANSIBLE_USER"
fi

echo "Ensuring SSH keypair exists for $ANSIBLE_USER..."
if [ ! -f "/home/$ANSIBLE_USER/.ssh/id_rsa" ]; then
    sudo -u "$ANSIBLE_USER" ssh-keygen -t rsa -b 4096 -N "" -f /home/$ANSIBLE_USER/.ssh/id_rsa
fi

echo "Moving shared key into special directory"
mkdir -p /etc/ansible/keys
cp /home/ansible/.ssh/id_rsa /etc/ansible/keys/ansible_id_rsa
chmod 640 /etc/ansible/keys/ansible_id_rsa
chgrp "$ANSIBLE_GROUP" /etc/ansible/keys/ansible_id_rsa


echo "Installing sshpass (required for initial bootstrapping)..."
sudo apt-get update -y
sudo apt-get install -y sshpass

###############################################################
# 2. Create Ansible project structure
###############################################################

for env in PRD DEV STG TST; do
    mkdir -p inventories/$env/group_vars
    mkdir -p inventories/$env/host_vars
    cat > inventories/$env/hosts.ini << EOF
# Hosts for environment: $env
[all]
# add hosts here
EOF
done

mkdir -p group_vars host_vars
mkdir -p roles
mkdir -p playbooks
mkdir -p library
mkdir -p filter_plugins
mkdir -p files
mkdir -p templates
mkdir -p vars
mkdir -p metadata
mkdir -p .githooks

###############################################################
# 3. ansible.cfg
###############################################################

cat > ansible.cfg << EOF
[defaults]
inventory = inventories/PRD/hosts.ini
roles_path = roles
collections_paths = collections
host_key_checking = False
retry_files_enabled = False
remote_user = ansible
private_key_file = /etc/ansible/keys/ansible_id_rsa
timeout = 30

[privilege_escalation]
become=True
become_method=sudo
become_ask_pass=False
EOF

###############################################################
# 4. site.yml
###############################################################

cat > site.yml << 'EOF'
---
# Master orchestration playbook
- import_playbook: playbooks/bootstrap.yml
EOF

cat > playbooks/bootstrap.yml << 'EOF'
---
- name: Prepare new hosts for Ansible usage
  hosts: new_hosts
  become: yes
  roles:
    - bootstrap
EOF

mkdir -p roles/bootstrap/{tasks,files}
cat > roles/bootstrap/tasks/main.yml << 'EOF'
---
- name: Bootstrap executed
  debug:
    msg: "Bootstrap executed"
EOF

###############################################################
# 5. Vault integration
###############################################################

mkdir -p vault
VAULT_FILE="$TARGET/.vault_pass"

if [ ! -f "$VAULT_FILE" ]; then
    echo "Generating vault password file..."
    openssl rand -base64 32 > "$VAULT_FILE"
    chmod 600 "$VAULT_FILE"
fi

echo ".vault_pass" >> .gitignore

for env in PRD DEV STG TST; do
    VAULT_YML="inventories/$env/group_vars/vault.yml"
    if [ ! -f "$VAULT_YML" ]; then
        cat > "$VAULT_YML" << EOF
# Encrypted secrets for $env environment
# Example:
# db_password: "changeme"
EOF
    fi
done

###############################################################
# 6. Permissions
###############################################################

echo "Fixing repo permissions..."
sudo chgrp -R "$ANSIBLE_GROUP" "$REPO_ROOT"
sudo chmod -R 2770 "$REPO_ROOT"
sudo chmod g+s "$TARGET"

###############################################################
# 7. Git repo initialization (local only now)
###############################################################

echo "Initializing local Git repository..."
git init
git branch -M master
git add .
git commit -m "Initial infrastructure repository"

echo "Infrastructure repository initialized successfully."
echo "Ansible user created, SSH key ensured, vault ready."
