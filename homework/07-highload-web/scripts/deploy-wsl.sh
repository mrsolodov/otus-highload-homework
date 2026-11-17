#!/usr/bin/env bash
set -euo pipefail

cd "$1/ansible"
ansible all -i inventory.local.ini -m ansible.builtin.ping
ansible-playbook -i inventory.local.ini site.yml
