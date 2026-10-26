"""Camada de acesso ao banco de dados SQLite.

O banco é um único arquivo (por padrão ``data/escola.db``). O caminho pode ser
trocado pela variável de ambiente ``DB_PATH`` (usada nos testes e na VM).
"""
import os
import sqlite3
from contextlib import contextmanager
from pathlib import Path

DB_PATH = os.getenv("DB_PATH", str(Path(__file__).resolve().parent.parent / "data" / "escola.db"))

SCHEMA = """
CREATE TABLE IF NOT EXISTS cursos (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    nome          TEXT    NOT NULL UNIQUE,
    descricao     TEXT,
    carga_horaria INTEGER NOT NULL CHECK (carga_horaria > 0)
);

CREATE TABLE IF NOT EXISTS alunos (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    nome            TEXT NOT NULL,
    email           TEXT NOT NULL UNIQUE,
    data_nascimento TEXT
);

CREATE TABLE IF NOT EXISTS matriculas (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    aluno_id       INTEGER NOT NULL REFERENCES alunos(id) ON DELETE CASCADE,
    curso_id       INTEGER NOT NULL REFERENCES cursos(id) ON DELETE CASCADE,
    data_matricula TEXT    NOT NULL DEFAULT (date('now')),
    UNIQUE (aluno_id, curso_id)
);
"""


def get_db_path() -> str:
    return os.getenv("DB_PATH", DB_PATH)


@contextmanager
def get_connection():
    """Abre uma conexão, faz commit no final e fecha sempre."""
    path = get_db_path()
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    novo = not Path(path).exists()
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    if novo:  # arquivo apagado/novo: recria as tabelas automaticamente
        conn.executescript(SCHEMA)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def init_db() -> None:
    """Cria as tabelas se ainda não existirem."""
    with get_connection() as conn:
        conn.executescript(SCHEMA)
