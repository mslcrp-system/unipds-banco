#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gerar_lista_vencimentos.py — Gera CSV da fila de prevencao de inadimplencia.

Chama a RPC faturamento.get_vencimentos_proximos (parcelas de assinatura
EM_ABERTO que vencem nos proximos N dias) e grava um CSV pronto para o
time de cobranca acionar os alunos ANTES do vencimento.

Uso:
    # Janela padrao (7 dias), ambos os tenants
    python scripts/gerar_lista_vencimentos.py

    # Outra janela
    python scripts/gerar_lista_vencimentos.py --dias 3
    python scripts/gerar_lista_vencimentos.py --dias 15

    # So um tenant
    python scripts/gerar_lista_vencimentos.py --tenant ia
    python scripts/gerar_lista_vencimentos.py --tenant java

    # Pasta de saida (default: scripts/listas/)
    python scripts/gerar_lista_vencimentos.py --out "G:/Meu Drive/Unipds/Clientes"

Requer scripts/.env com SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY.
"""

import argparse
import csv
import os
import sys
from datetime import datetime
from pathlib import Path

from dotenv import load_dotenv
from supabase import create_client

SCRIPT_DIR = Path(__file__).resolve().parent
load_dotenv(SCRIPT_DIR / ".env")

SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    print("ERRO: SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY devem estar em scripts/.env", file=sys.stderr)
    sys.exit(1)

TENANTS = {
    "ia":   "e717e24d-fb30-4ed0-83d3-bb8ea0b66783",
    "java": "70b668e4-be85-459b-8dbb-3876929ac850",
}

# Colunas na ordem do CSV (chave da RPC -> cabecalho amigavel)
COLUNAS = [
    ("tenant",          "Tenant"),
    ("aluno",           "Aluno"),
    ("cpf_cnpj",        "CPF/CNPJ"),
    ("telefone",        "Telefone"),
    ("email",           "Email"),
    ("produto",         "Produto"),
    ("numero_parcela",  "Parcela"),
    ("data_vencimento", "Vencimento"),
    ("dias_ate_vencer", "Dias ate vencer"),
    ("valor",           "Valor"),
    ("voomp_contrato_id", "Contrato Voomp"),
]


def log(msg: str) -> None:
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dias", type=int, default=7, help="Janela de vencimento (default 7)")
    ap.add_argument("--tenant", choices=["ia", "java"], default=None, help="Filtra um tenant (default: ambos)")
    ap.add_argument("--out", default=str(SCRIPT_DIR / "listas"), help="Pasta de saida do CSV")
    args = ap.parse_args()

    sb = create_client(SUPABASE_URL, SUPABASE_KEY)

    params = {"p_dias": args.dias, "p_tenant_id": TENANTS.get(args.tenant)}
    log(f"Consultando vencimentos (dias={args.dias}, tenant={args.tenant or 'ambos'})...")
    resp = sb.rpc("get_vencimentos_proximos", params).execute()
    linhas = resp.data or []

    if not linhas:
        log("Nenhuma parcela a vencer na janela. Nada a gerar.")
        return

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d")
    sufixo = args.tenant or "todos"
    out_path = out_dir / f"vencimentos_{sufixo}_{args.dias}d_{stamp}.csv"

    total_valor = 0.0
    with out_path.open("w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f, delimiter=";")
        w.writerow([cab for _, cab in COLUNAS])
        for r in linhas:
            w.writerow([r.get(chave, "") for chave, _ in COLUNAS])
            total_valor += float(r.get("valor") or 0)

    log(f"OK: {len(linhas)} parcelas, R$ {total_valor:,.2f}")
    log(f"CSV: {out_path}")


if __name__ == "__main__":
    main()
