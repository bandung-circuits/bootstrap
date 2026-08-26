#!/usr/bin/env bash
# provision-linux-vm.sh — run INSIDE the Linux ARM template VM to ready it for CI.
# Installs baseline deps + VMware tools + SSH hardening. Run once before snapshot.
set -euo pipefail
note(){ printf '==> %s\n' "$*"; }

note "updating apt and installing baseline deps"
sudo apt-get update -y
sudo apt-get install -y curl git python3 python3-pip python3-venv openssh-server open-vm-tools ca-certificates

note "ensuring sshd is on"
sudo systemctl enable --now ssh

note "provisioning complete. Now snapshot this VM as 'clean-base' from the host:
  vmrun -T fusion snapshot \"<vmx>\" clean-base"
