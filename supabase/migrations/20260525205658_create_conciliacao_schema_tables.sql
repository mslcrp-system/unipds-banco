
-- ══════════════════════════════════════════════════════════════════
-- Schema conciliacao — reconciliação mensal Pipe × Voomp
-- Parte 1: schema, tabelas e índices
-- ══════════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS conciliacao;

-- ── fechamentos_mensais ────────────────────────────────────────────
CREATE TABLE conciliacao.fechamentos_mensais (
  fechamento_id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id                   uuid        NOT NULL REFERENCES unipds.tenants(tenant_id),
  ano_mes                     text        NOT NULL CHECK (ano_mes ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  estado                      text        NOT NULL DEFAULT 'ABERTO'
                              CHECK (estado IN ('ABERTO','EM_REVISAO','FECHADO','REABERTO')),
  snapshot_gerado_em          timestamptz,
  -- fotografia financeira (preenchida ao fechar)
  faturamento_pipe_deals      integer,
  faturamento_pipe_valor      numeric(15,2),
  faturamento_voomp_contratos integer,
  faturamento_voomp_cobrado   numeric(15,2),
  faturamento_voomp_liquido   numeric(15,2),
  faturamento_voomp_reembolsos numeric(15,2),
  total_matches               integer,
  total_orfaos_pipe           integer,
  total_orfaos_voomp          integer,
  fechado_em                  timestamptz,
  hash_relatorio              text,
  created_at                  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, ano_mes)
);

-- ── pipe_deals ─────────────────────────────────────────────────────
CREATE TABLE conciliacao.pipe_deals (
  pipe_deal_id     bigint        NOT NULL,
  tenant_id        uuid          NOT NULL REFERENCES unipds.tenants(tenant_id),
  pessoa_id        bigint,
  titulo           text,
  valor            numeric(15,2) NOT NULL,
  funil            text,
  status           text          NOT NULL,
  ganho_em         timestamptz,
  proprietario     text,
  cpf_raw          text,
  cpf_clean        text,
  email_raw        text,
  email_clean      text,
  rg               text,
  telefone_raw     text,
  telefone_clean   text,
  pessoa_nome      text,
  pessoa_nome_norm text,
  ano_mes          text          NOT NULL CHECK (ano_mes ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  imported_at      timestamptz   NOT NULL DEFAULT now(),
  imported_by      uuid,
  created_at       timestamptz   NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, pipe_deal_id)
);

-- ── voomp_snapshot ─────────────────────────────────────────────────
-- Fotografia imutável dos contratos Voomp elegíveis para o mês.
-- Critério: venda à vista OU parcela 1 de assinatura com data_pagamento no mês.
CREATE TABLE conciliacao.voomp_snapshot (
  snapshot_id       uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  fechamento_id     uuid          NOT NULL REFERENCES conciliacao.fechamentos_mensais(fechamento_id) ON DELETE CASCADE,
  tenant_id         uuid          NOT NULL,
  ano_mes           text          NOT NULL,
  -- referência informativa ao unipds (sem FK hard para evolução independente)
  contract_id       uuid,
  voomp_contrato_id text,
  aluno_nome        text,
  aluno_nome_norm   text,         -- lowercase sem acentos para matching
  cpf_cnpj          text,
  email             text,
  produto_nome      text,
  tipo_cobranca     text,         -- 'Assinatura' | 'Único'
  data_pagamento    date,
  valor_cobrado     numeric(15,2),
  valor_recebido    numeric(15,2),
  reembolsado       boolean       NOT NULL DEFAULT false,
  created_at        timestamptz   NOT NULL DEFAULT now()
);

-- ── conciliacao_links ──────────────────────────────────────────────
CREATE TABLE conciliacao.conciliacao_links (
  link_id            uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid          NOT NULL,
  ano_mes            text          NOT NULL,
  pipe_deal_id       bigint        NOT NULL,
  snapshot_id        uuid          NOT NULL REFERENCES conciliacao.voomp_snapshot(snapshot_id) ON DELETE CASCADE,
  criterio           text          NOT NULL CHECK (criterio IN ('AUTO_CPF','AUTO_NOME','MANUAL')),
  confianca          integer       NOT NULL DEFAULT 100,
  divergencia_valor  numeric(15,2),
  divergencia_classe text          CHECK (divergencia_classe IN ('IDENTICO','CENTAVOS','CUPOM_PROVAVEL','MATERIAL')),
  created_at         timestamptz   NOT NULL DEFAULT now(),
  created_by         uuid,
  UNIQUE (tenant_id, ano_mes, pipe_deal_id),
  UNIQUE (tenant_id, ano_mes, snapshot_id)
);

-- ── ingestao_status ────────────────────────────────────────────────
CREATE TABLE conciliacao.ingestao_status (
  tenant_id     uuid        NOT NULL REFERENCES unipds.tenants(tenant_id),
  fonte_id      uuid        NOT NULL REFERENCES unipds.fontes(fonte_id),
  ano_mes       text        NOT NULL CHECK (ano_mes ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  status        text        NOT NULL DEFAULT 'PENDENTE' CHECK (status IN ('PENDENTE','COMPLETA')),
  confirmado_em timestamptz,
  PRIMARY KEY (tenant_id, fonte_id, ano_mes)
);

-- ── Índices ────────────────────────────────────────────────────────
CREATE INDEX ON conciliacao.pipe_deals (tenant_id, ano_mes);
CREATE INDEX ON conciliacao.pipe_deals (cpf_clean);
CREATE INDEX ON conciliacao.pipe_deals USING gin (pessoa_nome_norm gin_trgm_ops);

CREATE INDEX ON conciliacao.voomp_snapshot (fechamento_id);
CREATE INDEX ON conciliacao.voomp_snapshot (tenant_id, ano_mes);
CREATE INDEX ON conciliacao.voomp_snapshot (cpf_cnpj);
CREATE INDEX ON conciliacao.voomp_snapshot USING gin (aluno_nome_norm gin_trgm_ops);

CREATE INDEX ON conciliacao.conciliacao_links (tenant_id, ano_mes);
CREATE INDEX ON conciliacao.ingestao_status (tenant_id, ano_mes);
