#!/bin/bash

# Check if the correct number of arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <source_vm> <target_vm>"
    exit 1
fi

SOURCE_VM="$1"
TARGET_VM="$2"

# Check if source VM exists
if ! VBoxManage list vms | grep -q "\"$SOURCE_VM\""; then
    echo "Error: Source VM '$SOURCE_VM' does not exist."
    exit 1
fi

if ! command -v sshpass &> /dev/null; then
    echo "Error: sshpass is required but not installed."
    exit 1
fi

if ! command -v sshpass &> /dev/null; then
    echo "Error: sshpass is required but not installed."
    exit 1
fi


SOURCE_CFG_FILE=$(VBoxManage showvminfo "$SOURCE_VM" --machinereadable | grep "CfgFile=" | cut -d '"' -f2)
SOURCE_DIR=$(dirname "$SOURCE_CFG_FILE")
SOURCE_SSH_PASSWORD_FILE="$SOURCE_DIR/pw-root.txt"

if [ ! -f "$SOURCE_SSH_PASSWORD_FILE" ]; then
    echo "Error: Password file $SOURCE_SSH_PASSWORD_FILE not found."
    exit 1
fi


# Configuration - Adjust these values as needed
SSH_USER="root"            # SSH username for the guest VM
PORT=$((RANDOM % 55001 + 10000))

# Check if the port is open, we may ssh to machine that already exists
nc -z localhost $PORT
if [ $? -eq 0 ]; then
    echo "Port $PORT is open"
    exit 1
fi


echo "== CLONE"
VBoxManage clonevm $SOURCE_VM --snapshot=base    --name="$TARGET_VM"  --register
TARGET_CFG_FILE=$(VBoxManage showvminfo "$TARGET_VM" --machinereadable | grep "CfgFile=" | cut -d '"' -f2)
TARGET_DIR=$(dirname "$TARGET_CFG_FILE")

echo "== PORT FORWARDING"
VBoxManage modifyvm "$TARGET_VM" --natpf1 "guestssh,tcp,,$PORT,,22"
echo "$PORT" > "$TARGET_DIR/sshport.txt"

# Start cloned VM
echo "== Starting $TARGET_VM..."
VBoxManage startvm "$TARGET_VM"

sleep 10
#  SSH readiness check
echo "== Finalizing connection..."

until sshpass -f "$SOURCE_SSH_PASSWORD_FILE" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=4 -p $PORT "$SSH_USER@localhost" true; do
    sleep 4
done

# Connect to VM
echo "== Connecting to $TARGET_VM via SSH..."
#sshpass -f "$SOURCE_SSH_PASSWORD_FILE" ssh -p $PORT "$SSH_USER@localhost"

DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
echo "== Dotfiles directory: $DOTFILES_DIR"
sshpass -f "$SOURCE_SSH_PASSWORD_FILE" rsync -e "ssh -p $PORT"  -avzr "$DOTFILES_DIR/" "$SSH_USER@localhost:/tmp/dotfiles"

sshpass -f "$SOURCE_SSH_PASSWORD_FILE" ssh -p $PORT "$SSH_USER@localhost" /usr/bin/systemctl stop display-manager

sshpass -f "$SOURCE_SSH_PASSWORD_FILE" ssh -p $PORT "$SSH_USER@localhost" hostnamectl hostname "$TARGET_VM"

sshpass -f "$SOURCE_SSH_PASSWORD_FILE" ssh -p $PORT "$SSH_USER@localhost" /tmp/dotfiles/install-wipe.sh dotfiles
sleep 1

sshpass -f "$SOURCE_SSH_PASSWORD_FILE" ssh-copy-id -p $PORT -i ~/.ssh/id_rsa.pub root@localhost
sshpass -f "$SOURCE_SSH_PASSWORD_FILE" ssh-copy-id -p $PORT -i ~/.ssh/id_rsa.pub jan@localhost

sshpass -f "$SOURCE_SSH_PASSWORD_FILE" ssh -p $PORT "$SSH_USER@localhost"  jan-scramble-user-password jan > "$TARGET_DIR/pw-jan.txt"
sshpass -f "$SOURCE_SSH_PASSWORD_FILE" ssh -p $PORT "$SSH_USER@localhost"  jan-scramble-user-password root > "$TARGET_DIR/pw-root.txt"


sshpass -f "$TARGET_DIR/pw-root.txt" ssh -p $PORT "$SSH_USER@localhost" reboot



echo "=== DONE ==="