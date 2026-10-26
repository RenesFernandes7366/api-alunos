#!/usr/bin/env bash
# Teste de ponta a ponta com chamadas HTTP reais.
# Uso: ./scripts/smoke_test.sh http://IP-DA-VM   (padrão: http://127.0.0.1:8000)
set -euo pipefail
BASE="${1:-http://127.0.0.1:8000}"
J='Content-Type: application/json'

passo() { echo; echo "\$ $*"; }

passo curl $BASE/health
curl -s "$BASE/health"; echo

passo curl -X POST $BASE/cursos
curl -s -X POST "$BASE/cursos" -H "$J" \
  -d '{"nome":"Computação em Nuvem","descricao":"Fundamentos de Azure","carga_horaria":60}'; echo

passo curl -X POST $BASE/cursos
curl -s -X POST "$BASE/cursos" -H "$J" \
  -d '{"nome":"Banco de Dados","descricao":"SQL e modelagem","carga_horaria":80}'; echo

passo curl -X POST $BASE/alunos
curl -s -X POST "$BASE/alunos" -H "$J" \
  -d '{"nome":"Maria Silva","email":"maria@email.com","data_nascimento":"2001-05-14"}'; echo

passo curl -X POST $BASE/alunos
curl -s -X POST "$BASE/alunos" -H "$J" \
  -d '{"nome":"João Souza","email":"joao@email.com"}'; echo

passo curl -X POST $BASE/matriculas
curl -s -X POST "$BASE/matriculas" -H "$J" -d '{"aluno_id":1,"curso_id":1}'; echo
curl -s -X POST "$BASE/matriculas" -H "$J" -d '{"aluno_id":1,"curso_id":2}'; echo
curl -s -X POST "$BASE/matriculas" -H "$J" -d '{"aluno_id":2,"curso_id":1}'; echo

passo curl $BASE/alunos/1/cursos
curl -s "$BASE/alunos/1/cursos"; echo

passo "curl -X POST $BASE/matriculas  (duplicada -> 409)"
curl -s -w "  [HTTP %{http_code}]" -X POST "$BASE/matriculas" -H "$J" -d '{"aluno_id":1,"curso_id":1}'; echo

passo "curl $BASE/alunos/999  (inexistente -> 404)"
curl -s -w "  [HTTP %{http_code}]" "$BASE/alunos/999"; echo
