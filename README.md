# API Escola — Alunos, Cursos e Matrículas

API REST em **Python + FastAPI** com banco de dados **SQLite**, hospedada em uma **máquina virtual Linux na Microsoft Azure** (SKU `Standard_B1s`, Ubuntu 24.04 LTS, região Brazil South).

![Arquitetura](docs/diagramas/arquitetura.png)

## Funcionalidades

| Recurso     | Rotas                                                                 |
|-------------|------------------------------------------------------------------------|
| Status      | `GET /`, `GET /health`                                                 |
| Cursos      | `GET/POST /cursos`, `GET/PUT/DELETE /cursos/{id}`                      |
| Alunos      | `GET/POST /alunos`, `GET/PUT/DELETE /alunos/{id}`, `GET /alunos/{id}/cursos` |
| Matrículas  | `GET/POST /matriculas`, `DELETE /matriculas/{id}`                      |

A documentação interativa (Swagger) fica em **`/docs`** e a alternativa (ReDoc) em **`/redoc`**.

Códigos de resposta: `200` ok · `201` criado · `204` removido · `404` não encontrado · `409` conflito (e-mail/curso/matrícula repetidos) · `422` dados inválidos.

## Modelo de dados

![Modelo ER](docs/diagramas/modelo_er.png)

## Estrutura do projeto

```
api-alunos/
├── app/
│   ├── main.py          # rotas da API (FastAPI)
│   ├── database.py      # conexão e criação das tabelas SQLite
│   └── schemas.py       # validação dos dados (Pydantic)
├── tests/test_api.py    # 8 testes automatizados (pytest)
├── scripts/smoke_test.sh# teste HTTP de ponta a ponta (local ou na nuvem)
├── deploy/
│   ├── azure_criar_vm.sh# cria toda a infraestrutura na Azure (Azure CLI)
│   ├── cloud-init.yaml  # configura a VM no primeiro boot
│   └── atualizar_vm.sh  # atualiza a API após um novo push
├── docs/                # diagramas e prints de tela
├── requirements.txt
└── requirements-dev.txt
```

## Rodando localmente

```bash
python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements-dev.txt
uvicorn app.main:app --reload
# abra http://127.0.0.1:8000/docs
```

Testes:

```bash
pytest -v                    # testes automatizados
./scripts/smoke_test.sh      # chamadas HTTP reais na API rodando
```

## Publicando na Azure

Pré-requisitos: conta Azure e [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) com `az login` feito.

```bash
./deploy/azure_criar_vm.sh
```

O script cria Resource Group, VM, rede, IP público e libera a porta 80. Na primeira inicialização, o `cloud-init` instala Python, Nginx e Git, clona este repositório, instala as dependências e sobe a API como serviço `systemd`. Depois de ~3 minutos:

```bash
./scripts/smoke_test.sh http://IP-DA-VM
```

Para remover tudo e parar a cobrança: `az group delete --name rg-api-escola --yes`.

## Tecnologias

| Camada          | Tecnologia                                  |
|-----------------|---------------------------------------------|
| Linguagem       | Python 3.12                                 |
| Framework web   | FastAPI + Uvicorn (ASGI)                    |
| Validação       | Pydantic v2                                  |
| Banco de dados  | SQLite 3 (arquivo `escola.db`)              |
| Servidor web    | Nginx (proxy reverso)                       |
| Nuvem           | Azure VM `Standard_B1s`, Ubuntu 24.04 LTS   |
| Armazenamento   | Managed Disk Standard SSD LRS, 30 GiB       |
| Testes          | pytest + httpx                              |
