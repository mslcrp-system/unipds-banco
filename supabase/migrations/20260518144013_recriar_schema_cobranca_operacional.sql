
-- ─── SCHEMA COBRANCA ─────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS cobranca;

-- ─── 1. cobranca_casos ───────────────────────────────────────
-- Um caso por contrato inadimplente. FK para unipds.contracts.
CREATE TABLE cobranca.cobranca_casos (
  caso_id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contract_id               uuid NOT NULL REFERENCES unipds.contracts(contract_id) ON DELETE CASCADE,
  tenant_id                 uuid NOT NULL REFERENCES unipds.tenants(tenant_id),
  status                    text NOT NULL DEFAULT 'em_aberto'
                              CHECK (status IN ('em_aberto','em_contato','em_negociacao','acordo_ativo','pago','extrajudicial','baixado')),
  faixa_aging               text NOT NULL DEFAULT 'faixa_1'
                              CHECK (faixa_aging IN ('faixa_1','faixa_2','faixa_3','faixa_4')),
  valor_total_aberto        numeric(12,2),
  parcelas_vencidas         integer DEFAULT 0,
  valor_revertido           numeric(12,2),
  responsavel               text,
  data_abertura             date NOT NULL DEFAULT CURRENT_DATE,
  data_ultima_interacao     date,
  data_encerramento         date,
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now(),
  UNIQUE (contract_id)  -- um caso por contrato
);

-- ─── 2. cobranca_interacoes ───────────────────────────────────
CREATE TABLE cobranca.cobranca_interacoes (
  interacao_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  caso_id           uuid NOT NULL REFERENCES cobranca.cobranca_casos(caso_id) ON DELETE CASCADE,
  data_contato      date NOT NULL DEFAULT CURRENT_DATE,
  canal             text NOT NULL CHECK (canal IN ('whatsapp','telefone','email','outro')),
  mensagem_enviada  text,
  houve_retorno     boolean NOT NULL DEFAULT false,
  observacao        text,
  operador          text NOT NULL DEFAULT 'Operador',
  created_at        timestamptz NOT NULL DEFAULT now()
);

-- ─── 3. cobranca_negociacoes ──────────────────────────────────
CREATE TABLE cobranca.cobranca_negociacoes (
  negociacao_id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  caso_id                   uuid NOT NULL REFERENCES cobranca.cobranca_casos(caso_id) ON DELETE CASCADE,
  valor_total_acordado      numeric(12,2) NOT NULL,
  valor_entrada             numeric(12,2),
  parcelas_acordadas        integer,
  valor_parcela_acordo      numeric(12,2),
  data_acordo               date NOT NULL DEFAULT CURRENT_DATE,
  data_primeiro_vencimento  date,
  status                    text NOT NULL DEFAULT 'em_andamento'
                              CHECK (status IN ('em_andamento','cumprido','quebrado')),
  observacao                text,
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now()
);

-- ─── TRIGGERS updated_at ─────────────────────────────────────
CREATE TRIGGER tg_cobranca_casos_updated_at
  BEFORE UPDATE ON cobranca.cobranca_casos
  FOR EACH ROW EXECUTE FUNCTION unipds.tg_set_updated_at();

CREATE TRIGGER tg_cobranca_negociacoes_updated_at
  BEFORE UPDATE ON cobranca.cobranca_negociacoes
  FOR EACH ROW EXECUTE FUNCTION unipds.tg_set_updated_at();

-- ─── RLS: expõe para o role anon/authenticated via Supabase ──
ALTER TABLE cobranca.cobranca_casos        ENABLE ROW LEVEL SECURITY;
ALTER TABLE cobranca.cobranca_interacoes   ENABLE ROW LEVEL SECURITY;
ALTER TABLE cobranca.cobranca_negociacoes  ENABLE ROW LEVEL SECURITY;

-- Policies permissivas (painel interno, sem multi-tenant de usuário)
CREATE POLICY "allow_all_casos"        ON cobranca.cobranca_casos        FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "allow_all_interacoes"   ON cobranca.cobranca_interacoes   FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "allow_all_negociacoes"  ON cobranca.cobranca_negociacoes  FOR ALL USING (true) WITH CHECK (true);

-- ─── GRANT para roles Supabase ────────────────────────────────
GRANT USAGE ON SCHEMA cobranca TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA cobranca TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA cobranca TO anon, authenticated, service_role;
