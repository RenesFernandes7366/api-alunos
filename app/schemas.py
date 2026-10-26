"""Modelos de entrada e saída (validação com Pydantic)."""
from datetime import date
from typing import Optional

from pydantic import BaseModel, EmailStr, Field


class CursoIn(BaseModel):
    nome: str = Field(..., min_length=2, max_length=120, examples=["Computação em Nuvem"])
    descricao: Optional[str] = Field(None, max_length=500, examples=["Fundamentos de Azure"])
    carga_horaria: int = Field(..., gt=0, examples=[60])


class Curso(CursoIn):
    id: int


class AlunoIn(BaseModel):
    nome: str = Field(..., min_length=2, max_length=120, examples=["Maria Silva"])
    email: EmailStr = Field(..., examples=["maria@email.com"])
    data_nascimento: Optional[date] = Field(None, examples=["2001-05-14"])


class Aluno(AlunoIn):
    id: int


class MatriculaIn(BaseModel):
    aluno_id: int = Field(..., gt=0)
    curso_id: int = Field(..., gt=0)


class Matricula(MatriculaIn):
    id: int
    data_matricula: date
    aluno_nome: str
    curso_nome: str
