"""Testes automatizados da API (rodar com: pytest -v)."""
import pytest
from fastapi.testclient import TestClient


@pytest.fixture()
def client(tmp_path, monkeypatch):
    # cada teste usa um banco SQLite novo e isolado
    monkeypatch.setenv("DB_PATH", str(tmp_path / "teste.db"))
    from app.main import app

    with TestClient(app) as c:
        yield c


def criar_curso(client, nome="Computação em Nuvem", ch=60):
    return client.post("/cursos", json={"nome": nome, "descricao": "Azure", "carga_horaria": ch})


def criar_aluno(client, nome="Maria Silva", email="maria@email.com"):
    return client.post("/alunos", json={"nome": nome, "email": email, "data_nascimento": "2001-05-14"})


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_crud_curso(client):
    r = criar_curso(client)
    assert r.status_code == 201
    cid = r.json()["id"]

    assert client.get(f"/cursos/{cid}").json()["nome"] == "Computação em Nuvem"

    r = client.put(f"/cursos/{cid}", json={"nome": "Cloud", "descricao": None, "carga_horaria": 80})
    assert r.status_code == 200 and r.json()["carga_horaria"] == 80

    assert client.delete(f"/cursos/{cid}").status_code == 204
    assert client.get(f"/cursos/{cid}").status_code == 404


def test_curso_duplicado_retorna_409(client):
    criar_curso(client)
    assert criar_curso(client).status_code == 409


def test_validacao_carga_horaria(client):
    assert criar_curso(client, ch=0).status_code == 422


def test_crud_aluno(client):
    r = criar_aluno(client)
    assert r.status_code == 201
    aid = r.json()["id"]
    assert len(client.get("/alunos").json()) == 1

    r = client.put(f"/alunos/{aid}", json={"nome": "Maria S.", "email": "maria@email.com"})
    assert r.status_code == 200 and r.json()["nome"] == "Maria S."

    assert client.delete(f"/alunos/{aid}").status_code == 204
    assert client.get(f"/alunos/{aid}").status_code == 404


def test_email_invalido_e_duplicado(client):
    assert criar_aluno(client, email="nao-e-email").status_code == 422
    criar_aluno(client)
    assert criar_aluno(client, nome="Outra").status_code == 409


def test_matricula_fluxo_completo(client):
    aid = criar_aluno(client).json()["id"]
    cid = criar_curso(client).json()["id"]

    r = client.post("/matriculas", json={"aluno_id": aid, "curso_id": cid})
    assert r.status_code == 201
    body = r.json()
    assert body["aluno_nome"] == "Maria Silva" and body["curso_nome"] == "Computação em Nuvem"

    # matrícula repetida
    assert client.post("/matriculas", json={"aluno_id": aid, "curso_id": cid}).status_code == 409
    # cursos do aluno
    assert [c["id"] for c in client.get(f"/alunos/{aid}/cursos").json()] == [cid]
    # excluir aluno remove as matrículas em cascata
    client.delete(f"/alunos/{aid}")
    assert client.get("/matriculas").json() == []


def test_matricula_com_ids_inexistentes(client):
    assert client.post("/matriculas", json={"aluno_id": 99, "curso_id": 1}).status_code == 404
