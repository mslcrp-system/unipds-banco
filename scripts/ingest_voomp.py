#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ingest_voomp.py — Ingere XLSX da Voomp em raw_imports + raw_lines no Supabase.

Substitui a Edge Function ingest-voomp-xlsx, que estourava WORKER_RESOURCE_LIMIT
ao processar arquivos de ~14 MB. Roda na maquina local (ou via Antigravity).

Uso:
    # Ingerir + processar (default)
    python scripts/ingest_voomp.py <caminho_xlsx> --fonte ia
    python scripts/ingest_voomp.py <caminho_xlsx> --fonte java

    # So ingerir, sem chamar processar_raw_lines
    python scripts/ingest_voomp.py <caminho_xlsx> --fonte ia --sem-processar

    # So rodar processar_raw_lines (sem ingerir)
    python scripts/ingest_voomp.py --processar-only

Requer .env em scripts/.env com SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY,
DISCORD_WEBHOOK_URL (opcional).
"""

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import requests
from dotenv import load_dotenv
from supabase import create_client, Client

# ============================================================
# Configuracao
# ============================================================

SCRIPT_DIR = Path(__file__).resolve().parent
load_dotenv(SCRIPT_DIR / ".env")

SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
DISCORD_WEBHOOK_URL = os.environ.get("DISCORD_WEBHOOK_URL", "").strip()

if not SUPABASE_URL or not SUPABASE_KEY:
    print("ERRO: SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY devem estar em scripts/.env", file=sys.stderr)
    sys.exit(1)

FONTES = {
    "ia": {
        "fonte_id": "fa773a8a-afce-404c-bfde-2671b186ca3b",
        "nome": "Voomp IA",
    },
    "java": {
        "fonte_id": "ab644e93-a398-47b0-a88d-d41cf2055d46",
        "nome": "Voomp Java",
    },
}

BATCH_SIZE = 500

# ============================================================
# Helpers
# ============================================================

def log(msg: str) -> None:
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)


def notify_discord(payload: dict) -> None:
    """Manda payload Discord no formato dos embeds Omie. Silencia falhas."""
    if not DISCORD_WEBHOOK_URL:
        return
    try:
        requests.post(DISCORD_WEBHOOK_URL, json=payload, timeout=10)
    except Exception as e:
        log(f"WARN: discord falhou: {e}")


def discord_success(filename: str, fonte: str, total_linhas: int, import_id: str) -> None:
    notify_discord({
        "content": f"✅ **ingest_voomp.py** — {filename}",
        "embeds": [{
            "title": f"Ingestão concluída — {fonte}",
            "color": 0x4CAF50,
            "fields": [
                {"name": "Arquivo",      "value": filename,            "inline": False},
                {"name": "Fonte",        "value": fonte,                "inline": True},
                {"name": "Linhas",       "value": str(total_linhas),    "inline": True},
                {"name": "import_id",    "value": f"`{import_id}`",     "inline": False},
            ],
        }],
    })


def discord_duplicate(filename: str, import_id: str, total_linhas: int, imported_at: str) -> None:
    notify_discord({
        "content": f"⚠️ **ingest_voomp.py** — reingestão ignorada",
        "embeds": [{
            "title": "Arquivo já processado anteriormente",
            "color": 0xFFAA00,
            "fields": [
                {"name": "Arquivo",       "value": filename,            "inline": False},
                {"name": "Processado em", "value": imported_at,         "inline": True},
                {"name": "Linhas",        "value": str(total_linhas),   "inline": True},
                {"name": "import_id",     "value": f"`{import_id}`",    "inline": False},
            ],
        }],
    })


def discord_error(filename: str, etapa: str, erro: str) -> None:
    notify_discord({
        "content": f"🔴 **ingest_voomp.py** — erro em {filename}",
        "embeds": [{
            "title": "Falha na ingestão",
            "color": 0xE05454,
            "fields": [
                {"name": "Arquivo",   "value": filename,                          "inline": False},
                {"name": "Etapa",     "value": etapa,                             "inline": True},
                {"name": "Erro",      "value": f"`{erro[:300]}`",                  "inline": False},
                {"name": "Timestamp", "value": datetime.now(timezone.utc).isoformat(), "inline": True},
            ],
        }],
    })


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def to_json_safe(value):
    """Converte tipos pandas para JSON-serializable (Timestamps, NaN, etc)."""
    if pd.isna(value):
        return None
    if isinstance(value, pd.Timestamp):
        return value.isoformat()
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return value


# ============================================================
# Fluxo principal
# ============================================================

def ingerir(supabase: Client, xlsx_path: Path, fonte_arg: str) -> str | None:
    """Retorna import_id se ingestao nova, None se ja existia. Aborta em erro."""
    filename = xlsx_path.name
    fonte = FONTES.get(fonte_arg.lower())
    if not fonte:
        msg = f"Fonte invalida: {fonte_arg}. Use 'ia' ou 'java'."
        log(f"ERRO: {msg}")
        discord_error(filename, "validacao", msg)
        sys.exit(2)

    if not xlsx_path.exists():
        msg = f"Arquivo nao encontrado: {xlsx_path}"
        log(f"ERRO: {msg}")
        discord_error(filename, "arquivo", msg)
        sys.exit(2)

    log(f"Ingestao: {filename} (fonte: {fonte['nome']})")

    # 1. SHA256
    sha = sha256_file(xlsx_path)
    log(f"  SHA256: {sha[:16]}...")

    # 2. Dedup
    existente = (
        supabase.schema("unipds")
        .table("raw_imports")
        .select("import_id, total_linhas, imported_at")
        .eq("sha256_hash", sha)
        .maybe_single()
        .execute()
    )
    if existente and existente.data:
        d = existente.data
        log(f"  Arquivo ja processado em {d['imported_at']} (import_id={d['import_id']}, {d['total_linhas']} linhas)")
        discord_duplicate(filename, d["import_id"], d["total_linhas"], d["imported_at"])
        return None

    # 3. Parse XLSX
    log("  Lendo XLSX...")
    df = pd.read_excel(xlsx_path, engine="openpyxl", dtype=str)
    # Substituir NaN por string vazia para preservar comportamento da Edge Function
    df = df.fillna("")
    total = len(df)
    log(f"  Parse OK: {total} linhas")

    if total == 0:
        msg = "XLSX sem linhas de dados"
        log(f"ERRO: {msg}")
        discord_error(filename, "parse", msg)
        sys.exit(2)

    # 4. INSERT raw_imports
    imp = (
        supabase.schema("unipds")
        .table("raw_imports")
        .insert({
            "fonte_id":     fonte["fonte_id"],
            "nome_arquivo": filename,
            "sha256_hash":  sha,
            "total_linhas": total,
            "status":       "processing",
        })
        .execute()
    )
    if not imp.data:
        msg = "Falha INSERT raw_imports"
        log(f"ERRO: {msg}")
        discord_error(filename, "raw_imports", msg)
        sys.exit(3)

    import_id = imp.data[0]["import_id"]
    log(f"  raw_imports criado: {import_id}")

    # 5. BULK INSERT raw_lines em chunks
    rows = df.to_dict(orient="records")
    # Garantir que tudo eh JSON-safe
    rows = [{k: to_json_safe(v) for k, v in row.items()} for row in rows]

    inserted = 0
    for i in range(0, total, BATCH_SIZE):
        chunk = rows[i:i + BATCH_SIZE]
        payload = [{"import_id": import_id, "payload": r} for r in chunk]
        try:
            supabase.schema("unipds").table("raw_lines").insert(payload).execute()
            inserted += len(chunk)
            log(f"  Inseridas {inserted}/{total}...")
        except Exception as e:
            erro = str(e)
            log(f"  ERRO batch {i}: {erro}")
            supabase.schema("unipds").table("raw_imports").update({
                "status": "error",
                "erros":  erro[:500],
            }).eq("import_id", import_id).execute()
            discord_error(filename, "raw_lines", erro)
            sys.exit(3)

    # 6. Marca como done
    supabase.schema("unipds").table("raw_imports").update({
        "status":      "done",
        "processadas": inserted,
    }).eq("import_id", import_id).execute()

    log(f"  raw_lines inseridas: {inserted}")
    discord_success(filename, fonte["nome"], inserted, import_id)
    return import_id


def processar(supabase: Client) -> None:
    """Chama unipds.processar_raw_lines('full') e imprime stats."""
    log("Rodando processar_raw_lines('full')...")
    result = supabase.schema("unipds").rpc("processar_raw_lines", {"p_modo": "full"}).execute()
    log("Resultado:")
    for row in result.data or []:
        log(f"  {row['etapa']:20s} | inseridos: {row['inseridos']:6d} | atualizados: {row['atualizados']:6d} | skipped: {row['skipped']:5d}")


def main():
    parser = argparse.ArgumentParser(description="Ingere XLSX Voomp no Supabase.")
    parser.add_argument("xlsx", nargs="?", help="Caminho do arquivo XLSX. Omitir se --processar-only.")
    parser.add_argument("--fonte", choices=["ia", "java"], help="Fonte do arquivo (ia ou java).")
    parser.add_argument("--sem-processar", action="store_true", help="Nao chama processar_raw_lines apos a ingestao.")
    parser.add_argument("--processar-only", action="store_true", help="Nao ingere; so chama processar_raw_lines.")
    args = parser.parse_args()

    supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

    if args.processar_only:
        processar(supabase)
        return

    if not args.xlsx or not args.fonte:
        parser.error("xlsx e --fonte sao obrigatorios (ou use --processar-only).")

    import_id = ingerir(supabase, Path(args.xlsx), args.fonte)

    if import_id and not args.sem_processar:
        processar(supabase)

    log("Concluido.")


if __name__ == "__main__":
    main()
