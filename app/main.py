"""API Escola — cadastro de alunos, cursos e matrículas (FastAPI + SQLite)."""
import sqlite3
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException, Response, status

from .database import get_connection, init_db
from .schemas import Aluno, AlunoIn, Curso, CursoIn, Matricula, MatriculaIn

VERSION = "1.0.0"


@asynccontextmanager
async def lifespan(_: FastAPI):
    init_db()  # cria as tabelas na primeira execução
    yield


app = FastAPI(
    title="API Escola",
    description="API REST para cadastro de **alunos**, **cursos** e **matrículas**, "
    "com banco de dados SQLite e hospedagem em uma VM Linux na Azure.",
    version=VERSION,
    lifespan=lifespan,
)


def _404(entidade: str, id_: int):
    raise HTTPException(status_code=404, detail=f"{entidade} {id_} não encontrado(a)")


# ---------------------------------------------------------------- saúde
@app.get("/", tags=["Status"])
def raiz():
    return {"api": "API Escola", "versao": VERSION, "documentacao": "/docs"}


@app.get("/health", tags=["Status"])
def health():
    with get_connection() as conn:
        conn.execute("SELECT 1")
    return {"status": "ok", "banco": "sqlite", "horario_utc": datetime.now(timezone.utc).isoformat()}


# ---------------------------------------------------------------- cursos
@app.get("/cursos", response_model=list[Curso], tags=["Cursos"])
def listar_cursos():
    with get_connection() as conn:
        rows = conn.execute("SELECT * FROM cursos ORDER BY id").fetchall()
    return [dict(r) for r in rows]


@app.get("/cursos/{curso_id}", response_model=Curso, tags=["Cursos"])
def obter_curso(curso_id: int):
    with get_connection() as conn:
        row = conn.execute("SELECT * FROM cursos WHERE id = ?", (curso_id,)).fetchone()
    if not row:
        _404("Curso", curso_id)
    return dict(row)


@app.post("/cursos", response_model=Curso, status_code=status.HTTP_201_CREATED, tags=["Cursos"])
def criar_curso(curso: CursoIn):
    try:
        with get_connection() as conn:
            cur = conn.execute(
                "INSERT INTO cursos (nome, descricao, carga_horaria) VALUES (?, ?, ?)",
                (curso.nome, curso.descricao, curso.carga_horaria),
            )
            novo_id = cur.lastrowid
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=409, detail="Já existe um curso com esse nome")
    return {"id": novo_id, **curso.model_dump()}


@app.put("/cursos/{curso_id}", response_model=Curso, tags=["Cursos"])
def atualizar_curso(curso_id: int, curso: CursoIn):
    try:
        with get_connection() as conn:
            cur = conn.execute(
                "UPDATE cursos SET nome = ?, descricao = ?, carga_horaria = ? WHERE id = ?",
                (curso.nome, curso.descricao, curso.carga_horaria, curso_id),
            )
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=409, detail="Já existe um curso com esse nome")
    if cur.rowcount == 0:
        _404("Curso", curso_id)
    return {"id": curso_id, **curso.model_dump()}


@app.delete("/cursos/{curso_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["Cursos"])
def remover_curso(curso_id: int):
    with get_connection() as conn:
        cur = conn.execute("DELETE FROM cursos WHERE id = ?", (curso_id,))
    if cur.rowcount == 0:
        _404("Curso", curso_id)
    return Response(status_code=204)


# ---------------------------------------------------------------- alunos
@app.get("/alunos", response_model=list[Aluno], tags=["Alunos"])
def listar_alunos():
    with get_connection() as conn:
        rows = conn.execute("SELECT * FROM alunos ORDER BY id").fetchall()
    return [dict(r) for r in rows]


@app.get("/alunos/{aluno_id}", response_model=Aluno, tags=["Alunos"])
def obter_aluno(aluno_id: int):
    with get_connection() as conn:
        row = conn.execute("SELECT * FROM alunos WHERE id = ?", (aluno_id,)).fetchone()
    if not row:
        _404("Aluno", aluno_id)
    return dict(row)


@app.post("/alunos", response_model=Aluno, status_code=status.HTTP_201_CREATED, tags=["Alunos"])
def criar_aluno(aluno: AlunoIn):
    nasc = aluno.data_nascimento.isoformat() if aluno.data_nascimento else None
    try:
        with get_connection() as conn:
            cur = conn.execute(
                "INSERT INTO alunos (nome, email, data_nascimento) VALUES (?, ?, ?)",
                (aluno.nome, aluno.email, nasc),
            )
            novo_id = cur.lastrowid
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=409, detail="E-mail já cadastrado")
    return {"id": novo_id, **aluno.model_dump()}


@app.put("/alunos/{aluno_id}", response_model=Aluno, tags=["Alunos"])
def atualizar_aluno(aluno_id: int, aluno: AlunoIn):
    nasc = aluno.data_nascimento.isoformat() if aluno.data_nascimento else None
    try:
        with get_connection() as conn:
            cur = conn.execute(
                "UPDATE alunos SET nome = ?, email = ?, data_nascimento = ? WHERE id = ?",
                (aluno.nome, aluno.email, nasc, aluno_id),
            )
    except sqlite3.IntegrityError:
        raise HTTPException(status_code=409, detail="E-mail já cadastrado")
    if cur.rowcount == 0:
        _404("Aluno", aluno_id)
    return {"id": aluno_id, **aluno.model_dump()}


@app.delete("/alunos/{aluno_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["Alunos"])
def remover_aluno(aluno_id: int):
    with get_connection() as conn:
        cur = conn.execute("DELETE FROM alunos WHERE id = ?", (aluno_id,))
    if cur.rowcount == 0:
        _404("Aluno", aluno_id)
    return Response(status_code=204)


@app.get("/alunos/{aluno_id}/cursos", response_model=list[Curso], tags=["Alunos"])
def cursos_do_aluno(aluno_id: int):
    with get_connection() as conn:
        if not conn.execute("SELECT 1 FROM alunos WHERE id = ?", (aluno_id,)).fetchone():
            _404("Aluno", aluno_id)
        rows = conn.execute(
            """SELECT c.* FROM cursos c
               JOIN matriculas m ON m.curso_id = c.id
               WHERE m.aluno_id = ? ORDER BY c.id""",
            (aluno_id,),
        ).fetchall()
    return [dict(r) for r in rows]


# ---------------------------------------------------------------- matrículas
SQL_MATRICULA = """
SELECT m.id, m.aluno_id, m.curso_id, m.data_matricula,
       a.nome AS aluno_nome, c.nome AS curso_nome
FROM matriculas m
JOIN alunos a ON a.id = m.aluno_id
JOIN cursos c ON c.id = m.curso_id
"""


@app.get("/matriculas", response_model=list[Matricula], tags=["Matrículas"])
def listar_matriculas():
    with get_connection() as conn:
        rows = conn.execute(SQL_MATRICULA + " ORDER BY m.id").fetchall()
    return [dict(r) for r in rows]


@app.post("/matriculas", response_model=Matricula, status_code=status.HTTP_201_CREATED, tags=["Matrículas"])
def matricular(m: MatriculaIn):
    with get_connection() as conn:
        if not conn.execute("SELECT 1 FROM alunos WHERE id = ?", (m.aluno_id,)).fetchone():
            _404("Aluno", m.aluno_id)
        if not conn.execute("SELECT 1 FROM cursos WHERE id = ?", (m.curso_id,)).fetchone():
            _404("Curso", m.curso_id)
        try:
            cur = conn.execute(
                "INSERT INTO matriculas (aluno_id, curso_id) VALUES (?, ?)", (m.aluno_id, m.curso_id)
            )
        except sqlite3.IntegrityError:
            raise HTTPException(status_code=409, detail="Aluno já matriculado neste curso")
        row = conn.execute(SQL_MATRICULA + " WHERE m.id = ?", (cur.lastrowid,)).fetchone()
    return dict(row)


@app.delete("/matriculas/{matricula_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["Matrículas"])
def cancelar_matricula(matricula_id: int):
    with get_connection() as conn:
        cur = conn.execute("DELETE FROM matriculas WHERE id = ?", (matricula_id,))
    if cur.rowcount == 0:
        _404("Matrícula", matricula_id)
    return Response(status_code=204)
