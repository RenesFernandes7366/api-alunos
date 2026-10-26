#!/usr/bin/env bash
# Validação completa da API publicada na Azure.
# Roda no Azure Cloud Shell (Bash). Não deixa dados de teste no banco.
#
# Uso:
#   ./scripts/validar_nuvem.sh                       # testes da API + infraestrutura
#   ./scripts/validar_nuvem.sh --reiniciar           # inclui reinício da VM (persistência)
#   ./scripts/validar_nuvem.sh --sem-azure URL       # só testes HTTP (sem comandos az)
#   ./scripts/validar_nuvem.sh --reiniciar --pausar  # um grupo por tela, para tirar prints
# A saída completa é salva em validacao_AAAAMMDD_HHMMSS.txt
set -uo pipefail
export LC_ALL=C.UTF-8

IP="52.230.164.119"
BASE="http://$IP"
RG="rg-api-escola"
VM="vm-api-escola"
REINICIAR=0
AZURE=1
PAUSAR=0
for a in "$@"; do
  case "$a" in
    --reiniciar) REINICIAR=1 ;;
    --sem-azure) AZURE=0 ;;
    --pausar) PAUSAR=1 ;;
    http*) BASE="$a" ;;
  esac
done

LOG="validacao_$(TZ=America/Sao_Paulo date +%Y%m%d_%H%M%S).txt"
exec > >(tee -a "$LOG") 2>&1
agora() { TZ=America/Sao_Paulo date '+%d/%m/%Y %H:%M:%S'; }
TOTAL_GRUPOS=6; [[ $AZURE == 0 ]] && TOTAL_GRUPOS=4; [[ $REINICIAR == 1 ]] && TOTAL_GRUPOS=$((TOTAL_GRUPOS+1))
pausa() {
  if [[ $PAUSAR == 1 ]]; then
    echo
    read -rp "  >> Tire o print desta tela e pressione Enter para continuar... " _ </dev/tty
    clear >/dev/tty
  fi
}
grupo() {  # $1 = número, $2 = título
  [[ $1 != 1 ]] && pausa || true
  [[ $PAUSAR == 1 ]] && echo "API Escola – Validação na Azure  |  $BASE"
  echo; echo "[$1/$TOTAL_GRUPOS] $2   –   $(agora) (Brasília)"
  echo "--------------------------------------------------------------------------------"
}

J='Content-Type: application/json'
OK=0; FALHA=0; N=0
SUF=$(date +%s)

resultado() {  # $1 = descrição, $2 = esperado, $3 = obtido
  N=$((N+1))
  local desc="$1" pad=""
  local falta=$((50 - ${#desc}))
  (( falta > 0 )) && pad=$(printf '%*s' "$falta" '')
  if [[ "$2" == "$3" ]]; then
    OK=$((OK+1)); printf "  ✅ %-2s %s%s  esperado %-10s obtido %s\n" "$N" "$desc" "$pad" "$2" "$3"
  else
    FALHA=$((FALHA+1)); printf "  ❌ %-2s %s%s  esperado %-10s obtido %s\n" "$N" "$desc" "$pad" "$2" "$3"
  fi
}
http() { curl -s -o /tmp/resp.json -w "%{http_code}" -m 15 "$@"; }
campo() { python3 -c "import json,sys;d=json.load(open('/tmp/resp.json'));print(d$1)" 2>/dev/null; }

[[ $PAUSAR == 1 ]] && clear >/dev/tty
echo "=============================================================="
echo " VALIDAÇÃO DA API ESCOLA NA AZURE"
echo " Alvo: $BASE"
echo " Início: $(agora) (Brasília)"
echo "=============================================================="

grupo 1 "Disponibilidade"
resultado "GET /health responde"                       200 "$(http "$BASE/health")"
resultado "Banco de dados SQLite conectado"            ok  "$(campo "['status']")"
resultado "Documentação Swagger em /docs"              200 "$(http "$BASE/docs")"
resultado "Especificação OpenAPI em /openapi.json"     200 "$(http "$BASE/openapi.json")"

grupo 2 "Fluxo completo (CRUD)"
resultado "POST /cursos cria curso"                    201 "$(http -X POST "$BASE/cursos" -H "$J" -d "{\"nome\":\"Validação $SUF\",\"descricao\":\"teste\",\"carga_horaria\":40}")"
CID=$(campo "['id']")
resultado "POST /alunos cria aluno"                    201 "$(http -X POST "$BASE/alunos" -H "$J" -d "{\"nome\":\"Aluno Validação\",\"email\":\"valida$SUF@teste.com\"}")"
AID=$(campo "['id']")
resultado "GET /alunos/{id} consulta aluno"            200 "$(http "$BASE/alunos/$AID")"
resultado "PUT /cursos/{id} atualiza curso"            200 "$(http -X PUT "$BASE/cursos/$CID" -H "$J" -d "{\"nome\":\"Validação $SUF\",\"descricao\":\"editado\",\"carga_horaria\":60}")"
resultado "Carga horária atualizada para 60"           60  "$(campo "['carga_horaria']")"
resultado "POST /matriculas matricula aluno"           201 "$(http -X POST "$BASE/matriculas" -H "$J" -d "{\"aluno_id\":$AID,\"curso_id\":$CID}")"
MID=$(campo "['id']")
http "$BASE/alunos/$AID/cursos" >/dev/null
resultado "GET /alunos/{id}/cursos lista o curso"      "$CID" "$(campo "[0]['id']")"

grupo 3 "Validações e erros esperados"
resultado "E-mail duplicado é recusado"                409 "$(http -X POST "$BASE/alunos" -H "$J" -d "{\"nome\":\"Outro\",\"email\":\"valida$SUF@teste.com\"}")"
resultado "E-mail inválido é recusado"                 422 "$(http -X POST "$BASE/alunos" -H "$J" -d '{"nome":"Outro","email":"abc"}')"
resultado "Carga horária zero é recusada"              422 "$(http -X POST "$BASE/cursos" -H "$J" -d '{"nome":"Invalido","carga_horaria":0}')"
resultado "Matrícula duplicada é recusada"             409 "$(http -X POST "$BASE/matriculas" -H "$J" -d "{\"aluno_id\":$AID,\"curso_id\":$CID}")"
resultado "Aluno inexistente retorna 404"              404 "$(http "$BASE/alunos/999999")"

grupo 4 "Exclusão e limpeza dos dados de teste"
resultado "DELETE /matriculas/{id}"                    204 "$(http -X DELETE "$BASE/matriculas/$MID")"
resultado "DELETE /alunos/{id}"                        204 "$(http -X DELETE "$BASE/alunos/$AID")"
resultado "DELETE /cursos/{id}"                        204 "$(http -X DELETE "$BASE/cursos/$CID")"
resultado "Aluno removido não é mais encontrado"       404 "$(http "$BASE/alunos/$AID")"

if [[ $AZURE == 1 ]]; then
  grupo 5 "Segurança de rede (NSG)"
  if curl -s -m 5 "http://$IP:8000/health" >/dev/null 2>&1; then P8000=aberta; else P8000=bloqueada; fi
  resultado "Porta 8000 (Uvicorn) fechada para a internet" bloqueada "$P8000"
  if curl -s -m 5 "http://$IP:5432" >/dev/null 2>&1; then PX=aberta; else PX=bloqueada; fi
  resultado "Porta qualquer (5432) bloqueada pelo NSG"   bloqueada "$PX"

  grupo 6 "Infraestrutura na Azure"
  resultado "VM em execução"                             "VM running" "$(az vm get-instance-view -g $RG -n $VM --query "instanceView.statuses[1].displayStatus" -o tsv 2>/dev/null)"
  resultado "Tamanho (SKU) da VM"                        Standard_B2pts_v2 "$(az vm show -g $RG -n $VM --query hardwareProfile.vmSize -o tsv 2>/dev/null)"
  resultado "Região da VM"                               centralus "$(az vm show -g $RG -n $VM --query location -o tsv 2>/dev/null)"
  echo "  ... consultando serviços dentro da VM (cerca de 1 minuto)"
  SAIDA=$(az vm run-command invoke -g $RG -n $VM --command-id RunShellScript \
    --scripts "echo API=\$(systemctl is-active api-escola); echo NGINX=\$(systemctl is-active nginx); echo DB=\$(test -f /var/lib/api-escola/escola.db && echo existe || echo ausente); echo BOOT=\$(systemctl is-enabled api-escola)" \
    --query "value[0].message" -o tsv 2>/dev/null)
  resultado "Serviço api-escola (systemd) ativo"         active  "$(echo "$SAIDA" | grep -o 'API=[a-z]*' | cut -d= -f2)"
  resultado "Serviço nginx ativo"                        active  "$(echo "$SAIDA" | grep -o 'NGINX=[a-z]*' | cut -d= -f2)"
  resultado "Arquivo escola.db no disco"                 existe  "$(echo "$SAIDA" | grep -o 'DB=[a-z]*' | cut -d= -f2)"
  resultado "API configurada para iniciar no boot"       enabled "$(echo "$SAIDA" | grep -o 'BOOT=[a-z]*' | cut -d= -f2)"
fi

if [[ $REINICIAR == 1 ]]; then
  grupo $TOTAL_GRUPOS "Persistência após reiniciar a VM"
  http -X POST "$BASE/alunos" -H "$J" -d "{\"nome\":\"Persistencia\",\"email\":\"persist$SUF@teste.com\"}" >/dev/null
  PID=$(campo "['id']")
  ANTES=$(http "$BASE/alunos" >/dev/null; campo ".__len__()")
  echo "  ... reiniciando a VM (2 a 3 minutos)"
  az vm restart -g $RG -n $VM -o none
  for i in $(seq 1 30); do [[ "$(http "$BASE/health")" == 200 ]] && break; sleep 10; done
  resultado "API volta sozinha após o reinício"          200 "$(http "$BASE/health")"
  DEPOIS=$(http "$BASE/alunos" >/dev/null; campo ".__len__()")
  resultado "Total de alunos igual antes/depois ($ANTES)" "$ANTES" "$DEPOIS"
  resultado "Aluno gravado antes do reinício existe"      200 "$(http "$BASE/alunos/$PID")"
  http -X DELETE "$BASE/alunos/$PID" >/dev/null
fi

pausa
echo
echo "=============================================================="
echo " RESULTADO: $OK de $N testes aprovados  |  $FALHA falha(s)"
echo " Fim: $(agora) (Brasília)
 Log salvo em: $LOG"
echo "=============================================================="
[[ $FALHA == 0 ]]
