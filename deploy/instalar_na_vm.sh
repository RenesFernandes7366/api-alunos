#!/usr/bin/env bash
# Instala/reinstala a API dentro da VM (executado como root).
# Faz o mesmo que o cloud-init e pode ser rodado quantas vezes quiser.
# Uso (no Cloud Shell, dentro da pasta do projeto):
#   az vm run-command invoke -g rg-api-escola -n vm-api-escola --command-id RunShellScript \
#      --scripts @deploy/instalar_na_vm.sh --query "value[0].message" -o tsv
set -uo pipefail
REPO_URL="https://github.com/RenesFernandes7366/api-alunos.git"
APP=/opt/api-escola
DATA=/var/lib/api-escola

echo "== Diagnóstico do cloud-init"
cloud-init status --long 2>/dev/null | head -4
grep -iE "error|fail|Traceback" /var/log/cloud-init-output.log 2>/dev/null | tail -3

echo "== Instalando pacotes"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y -qq python3-venv python3-pip nginx git sqlite3 >/dev/null && echo "ok"

echo "== Baixando o projeto"
if [ -d "$APP/.git" ]; then
  git config --global --add safe.directory "$APP"
  git -C "$APP" pull -q && echo "atualizado"
else
  rm -rf "$APP" && git clone -q "$REPO_URL" "$APP" && echo "clonado"
fi

echo "== Ambiente Python"
python3 -m venv "$APP/.venv"
"$APP/.venv/bin/pip" install -q -r "$APP/requirements.txt" && echo "dependências ok"
mkdir -p "$DATA"
chown -R www-data:www-data "$DATA" "$APP"

echo "== Serviço systemd"
cat > /etc/systemd/system/api-escola.service <<'EOF'
[Unit]
Description=API Escola (FastAPI + SQLite)
After=network.target

[Service]
User=www-data
WorkingDirectory=/opt/api-escola
Environment=DB_PATH=/var/lib/api-escola/escola.db
ExecStart=/opt/api-escola/.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000 --workers 1
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable -q --now api-escola
systemctl restart api-escola

echo "== Nginx"
cat > /etc/nginx/sites-available/api-escola <<'EOF'
server {
    listen 80 default_server;
    server_name _;
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOF
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/api-escola /etc/nginx/sites-enabled/api-escola
nginx -t -q && systemctl enable -q nginx && systemctl restart nginx

echo "== Resultado"
sleep 3
echo "api-escola: $(systemctl is-active api-escola) | nginx: $(systemctl is-active nginx)"
curl -s http://localhost/health; echo
