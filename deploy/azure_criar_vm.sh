#!/usr/bin/env bash
# Cria toda a infraestrutura na Azure e publica a API.
# Pré-requisitos: Azure CLI instalada e "az login" feito.
# Uso: ./deploy/azure_criar_vm.sh   (opcional: URL de outro repositório)
set -euo pipefail

REPO_URL="${1:-https://github.com/RenesFernandes7366/api-alunos.git}"
RG="rg-api-escola"            # Resource Group
LOCATION="brazilsouth"         # Região (São Paulo)
VM="vm-api-escola"
SIZE="Standard_B1s"            # SKU: 1 vCPU, 1 GiB RAM
IMAGE="Ubuntu2404"             # Ubuntu Server 24.04 LTS
ADMIN="azureuser"

DIR="$(cd "$(dirname "$0")" && pwd)"
sed "s|__REPO_URL__|$REPO_URL|" "$DIR/cloud-init.yaml" > /tmp/cloud-init-api-escola.yaml

echo ">> Criando Resource Group"
az group create --name "$RG" --location "$LOCATION" -o table

echo ">> Criando VM (rede virtual, IP público, NSG e disco são criados junto)"
az vm create \
  --resource-group "$RG" \
  --name "$VM" \
  --image "$IMAGE" \
  --size "$SIZE" \
  --admin-username "$ADMIN" \
  --generate-ssh-keys \
  --public-ip-sku Standard \
  --storage-sku StandardSSD_LRS \
  --os-disk-size-gb 30 \
  --custom-data /tmp/cloud-init-api-escola.yaml \
  -o table

echo ">> Liberando a porta 80 (HTTP) no Network Security Group"
az vm open-port --resource-group "$RG" --name "$VM" --port 80 --priority 1010 -o none

IP=$(az vm show -d -g "$RG" -n "$VM" --query publicIps -o tsv)
echo
echo "Pronto! Aguarde ~3 minutos para o cloud-init terminar e acesse:"
echo "  http://$IP/docs"
echo "  http://$IP/health"
echo
echo "Para apagar tudo depois (e parar a cobrança):"
echo "  az group delete --name $RG --yes --no-wait"
