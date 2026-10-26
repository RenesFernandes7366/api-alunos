#!/usr/bin/env bash
# Cria toda a infraestrutura na Azure e publica a API.
# Pré-requisitos: Azure CLI instalada e "az login" feito (o Cloud Shell já vem pronto).
#
# Uso:
#   ./deploy/azure_criar_vm.sh
# Trocar região e/ou tamanho da VM:
#   LOCATION=eastus SIZE=Standard_B2ats_v2 ./deploy/azure_criar_vm.sh
set -euo pipefail

REPO_URL="${1:-https://github.com/RenesFernandes7366/api-alunos.git}"
RG="${RG:-rg-api-escola}"                  # Resource Group
LOCATION="${LOCATION:-brazilsouth}"        # Região (padrão: São Paulo)
VM="${VM:-vm-api-escola}"
SIZE="${SIZE:-Standard_B1s}"               # SKU: 1 vCPU, 1 GiB RAM
ADMIN="azureuser"

# Tamanhos com "p" (ex.: Standard_B2pts_v2) usam processador Arm e precisam da imagem Arm64.
if [[ "$SIZE" =~ ^Standard_[A-Z][0-9]+[a-z]*p ]]; then
  IMAGE="${IMAGE:-Canonical:ubuntu-24_04-lts:server-arm64:latest}"   # Ubuntu 24.04 LTS (Arm64)
  EXTRA_ARGS=(--security-type Standard)
else
  IMAGE="${IMAGE:-Ubuntu2404}"                                       # Ubuntu 24.04 LTS (x64)
  EXTRA_ARGS=()
fi

DIR="$(cd "$(dirname "$0")" && pwd)"
sed "s|__REPO_URL__|$REPO_URL|" "$DIR/cloud-init.yaml" > /tmp/cloud-init-api-escola.yaml

mostrar_erro_real() {
  echo
  echo "!! A criação falhou. Mensagens de erro registradas pela Azure:"
  az monitor activity-log list --resource-group "$RG" --offset 1h --status Failed \
    --query "[].properties.statusMessage" -o tsv 2>/dev/null | sort -u | head -5 || true
  echo
  echo "Dicas:"
  echo "  - 'RequestDisallowedByAzure' ou 'policy': sua assinatura não permite essa região."
  echo "    Veja as regiões liberadas:  az policy assignment list --query \"[].parameters\" -o json"
  echo "  - 'SkuNotAvailable' ou 'quota': troque o tamanho ou a região, por exemplo:"
  echo "    LOCATION=eastus SIZE=Standard_B2ats_v2 ./deploy/azure_criar_vm.sh"
  exit 1
}

echo ">> Região: $LOCATION | Tamanho (SKU): $SIZE | Imagem: $IMAGE"
echo ">> Verificando se o tamanho $SIZE está disponível em $LOCATION"
DISP=$(az vm list-skus --location "$LOCATION" --size "$SIZE" --resource-type virtualMachines \
  --query "[?name=='$SIZE'] | [0].{n:name, r:length(restrictions)}" -o tsv 2>/dev/null || true)
if [[ -z "$DISP" ]]; then
  echo "!! O tamanho $SIZE não existe na região $LOCATION."
  echo "   Tamanhos B disponíveis nessa região:"
  az vm list-skus --location "$LOCATION" --size Standard_B --resource-type virtualMachines \
    --query "[?length(restrictions)==\`0\`].name" -o tsv | head -15
  exit 1
elif [[ "$(echo "$DISP" | awk '{print $2}')" != "0" ]]; then
  echo "!! O tamanho $SIZE está bloqueado para a sua assinatura em $LOCATION."
  echo "   Tamanhos B liberados nessa região:"
  az vm list-skus --location "$LOCATION" --size Standard_B --resource-type virtualMachines \
    --query "[?length(restrictions)==\`0\`].name" -o tsv | head -15
  echo "   Rode de novo com, por exemplo: SIZE=Standard_B2ats_v2 ./deploy/azure_criar_vm.sh"
  exit 1
fi
echo "   OK, disponível."

echo ">> Criando Resource Group (se ainda não existir)"
if [[ "$(az group exists --name "$RG")" != "true" ]]; then
  az group create --name "$RG" --location "$LOCATION" -o table
fi

echo ">> Criando VM (rede virtual, IP público, NSG e disco são criados junto)"
az vm create \
  --resource-group "$RG" \
  --name "$VM" \
  --location "$LOCATION" \
  --image "$IMAGE" \
  --size "$SIZE" \
  --admin-username "$ADMIN" \
  --generate-ssh-keys \
  --public-ip-sku Standard \
  --storage-sku StandardSSD_LRS \
  --os-disk-size-gb 30 \
  --custom-data /tmp/cloud-init-api-escola.yaml \
  "${EXTRA_ARGS[@]}" \
  -o table || mostrar_erro_real

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
