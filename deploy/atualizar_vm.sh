#!/usr/bin/env bash
# Atualiza a API na VM depois de um novo "git push".
# Uso (no seu computador): ssh azureuser@IP-DA-VM 'bash -s' < deploy/atualizar_vm.sh
set -euo pipefail
cd /opt/api-escola
sudo -u www-data git pull
sudo -u www-data .venv/bin/pip install -q -r requirements.txt
sudo systemctl restart api-escola
systemctl --no-pager status api-escola | head -5
