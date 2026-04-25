#!/usr/bin/env bash
set -euo pipefail

# Bootstrap Ansible on Linux Mint 22 (Ubuntu 24.04 base).
# Then run the Resolve playbook.

if ! command -v apt >/dev/null 2>&1; then
  echo "ERROR: apt not found. This script targets Linux Mint/Ubuntu."
  exit 1
fi

sudo apt update
sudo apt install -y software-properties-common ca-certificates curl git

# Install Ansible (Mint/Ubuntu package)
sudo apt install -y ansible

echo ""
echo "Ansible installed: $(ansible --version | head -n 1)"
echo ""
echo "Next:"
echo "  1) Put the Resolve .run/deb installer in ./files/ if installing Resolve"
echo "  2) Run: ansible-playbook -K site.yml"
