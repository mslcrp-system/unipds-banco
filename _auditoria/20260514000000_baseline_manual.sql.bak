-- =============================================================================
-- BASELINE: Schema completo do banco UnipdsBanco
-- Extraído em 2026-05-14 via MCP Supabase
-- Schemas: unipds, cobranca
-- =============================================================================

-- EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "pg_trgm" WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;

-- SCHEMAS
CREATE SCHEMA IF NOT EXISTS unipds;
CREATE SCHEMA IF NOT EXISTS cobranca;

-- ENUMS
CREATE TYPE cobranca.canal_contato AS ENUM ('whatsapp', 'telefone');
CREATE TYPE cobranca.faixa_aging AS ENUM ('faixa_1', 'faixa_2', 'faixa_3', 'faixa_4');
CREATE TYPE cobranca.mensagem_regime AS ENUM ('A', 'B', 'C', 'D', 'E', 'F', 'personalizada');
CREATE TYPE cobranca.status_acordo AS ENUM ('em_andamento', 'cumprido', 'quebrado');
CREATE TYPE cobranca.status_caso AS ENUM ('em_aberto', 'em_contato', 'em_negociacao', 'acordo_ativo', 'pago', 'extrajudicial', 'baixado');

-- TABLES unipds
CREATE TABLE IF NOT EXISTS unipds.tenants (
  tenant_id uuid DEFAULT gen_random_uuid() NOT NULL,
  nome text NOT NULL,
  cnpj text NOT NULL,
  ativo boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS unipds.products (
  product_id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  voomp_produto_id text,
  nome text NOT NULL,
  tipo text,
  categoria text,
  ativo boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS unipds.fontes (
  fonte_id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  nome text NOT NULL,
  plataforma text DEFAULT 'voomp'::text NOT NULL,
  config jsonb,
  ativo boolean DEFAULT true NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS unipds.students (
  student_id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  cpf_cnpj text NOT NULL,
  nome text NOT NULL,
  email text,
  telefone text,
  endereco jsonb,
  uf_origem text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS unipds.contracts (
  contract_id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  fonte_id uuid NOT NULL,
  student_id uuid NOT NULL,
  product_id uuid NOT NULL,
  voomp_contrato_id text,
  contract_ref text NOT NULL,
  voomp_oferta_id text,
  nome_oferta text,
  tipo_cobranca text NOT NULL,
  periodo text,
  recorrencia_total integer,
  valor_oferta numeric NOT NULL,
  status_contrato text NOT NULL,
  data_primeira_venda date,
  data_encerramento date,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  contrato_canonico boolean DEFAULT true NOT NULL,
  contrato_espelho_de uuid
);
CREATE TABLE IF NOT EXISTS unipds.charges (
  charge_id uuid DEFAULT gen_random_uuid() NOT NULL,
  contract_id uuid NOT NULL,
  voomp_venda_id text NOT NULL,
  numero_parcela integer,
  forma_pagamento integer,
  valor_cobrado numeric NOT NULL,
  taxa_voomp numeric,
  comissao_coprodutor numeric,
  valor_recebido numeric,
  metodo_pagamento text,
  status text NOT NULL,
  data_vencimento date,
  data_pagamento date,
  data_liberacao_saldo date,
  dias_atraso integer DEFAULT 0 NOT NULL,
  link_boleto text,
  chave_pix text,
  nota_fiscal text,
  cupom text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  faturamento_total numeric,
  valor_oferta_linha numeric
);
CREATE TABLE IF NOT EXISTS unipds.previsao_parcelas (
  previsao_id uuid DEFAULT gen_random_uuid() NOT NULL,
  contract_id uuid NOT NULL,
  tenant_id uuid NOT NULL,
  numero_parcela integer NOT NULL,
  total_parcelas integer NOT NULL,
  previsao_ref text NOT NULL,
  valor_previsto numeric NOT NULL,
  data_prevista date,
  data_pagamento date,
  charge_id uuid,
  status text DEFAULT 'previsto'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS unipds.payment_attempts (
  attempt_id uuid DEFAULT gen_random_uuid() NOT NULL,
  contract_id uuid NOT NULL,
  voomp_venda_id text NOT NULL,
  metodo_pagamento text,
  forma_pagamento integer,
  valor numeric,
  motivo_recusa text,
  tentativa_em timestamp with time zone
);
CREATE TABLE IF NOT EXISTS unipds.refunds (
  refund_id uuid DEFAULT gen_random_uuid() NOT NULL,
  charge_id uuid NOT NULL,
  voomp_venda_id text NOT NULL,
  tipo text NOT NULL,
  valor numeric NOT NULL,
  motivo text,
  ocorrido_em timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS unipds.raw_imports (
  import_id uuid DEFAULT gen_random_uuid() NOT NULL,
  fonte_id uuid NOT NULL,
  nome_arquivo text NOT NULL,
  sha256_hash text NOT NULL,
  total_linhas integer,
  processadas integer DEFAULT 0,
  erros integer DEFAULT 0,
  status text DEFAULT 'pendente'::text NOT NULL,
  imported_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS unipds.raw_lines (
  line_id uuid DEFAULT gen_random_uuid() NOT NULL,
  import_id uuid NOT NULL,
  linha_numero integer NOT NULL,
  payload jsonb NOT NULL,
  status text DEFAULT 'pendente'::text NOT NULL,
  erro_msg text,
  processed_at timestamp with time zone
);
CREATE TABLE IF NOT EXISTS unipds.pipe_deals (
  pipe_deal_id bigint NOT NULL,
  tenant_id uuid NOT NULL,
  pessoa_id bigint,
  titulo text NOT NULL,
  valor numeric NOT NULL,
  funil text,
  status text NOT NULL,
  ganho_em timestamp with time zone,
  data_perda timestamp with time zone,
  proprietario text,
  cpf_raw text,
  cpf_clean text,
  email_raw text,
  email_clean text,
  rg text,
  telefone_raw text,
  telefone_clean text,
  organizacao text,
  pessoa_nome text,
  pessoa_nome_norm text,
  ano_mes text NOT NULL,
  imported_at timestamp with time zone DEFAULT now() NOT NULL,
  imported_by uuid,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS unipds.fechamentos_mensais (
  fechamento_id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  ano_mes text NOT NULL,
  estado text DEFAULT 'ABERTO'::text NOT NULL,
  total_pipe_deals integer,
  total_voomp_alunos integer,
  total_matches integer,
  total_orfaos_pipe integer,
  total_orfaos_voomp integer,
  hash_relatorio text,
  arquivo_relatorio_url text,
  fechado_em timestamp with time zone,
  fechado_por uuid,
  reaberto_em timestamp with time zone,
  reaberto_por uuid,
  motivo_reabertura text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  ingestao_validada_em timestamp with time zone,
  ingestao_validada_por uuid
);
CREATE TABLE IF NOT EXISTS unipds.ingestao_status (
  ingestao_status_id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  fonte_id uuid NOT NULL,
  ano_mes text NOT NULL,
  status text DEFAULT 'PARCIAL'::text NOT NULL,
  total_registros integer,
  ultimo_import_id uuid,
  confirmado_em timestamp with time zone,
  confirmado_por uuid,
  observacao text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS unipds.conciliacao_runs (
  run_id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  ano_mes text NOT NULL,
  fechamento_id uuid,
  iniciado_em timestamp with time zone DEFAULT now() NOT NULL,
  finalizado_em timestamp with time zone,
  status text DEFAULT 'EM_EXECUCAO'::text NOT NULL,
  total_pipe_avaliados integer,
  total_voomp_avaliados integer,
  matches_cpf integer,
  matches_email integer,
  matches_nome integer,
  matches_telefone integer,
  matches_manual integer,
  orfaos_pipe integer,
  orfaos_voomp integer,
  parametros jsonb,
  erro_msg text,
  executado_por uuid
);
CREATE TABLE IF NOT EXISTS unipds.conciliacao_links (
  link_id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  ano_mes text NOT NULL,
  pipe_deal_id bigint NOT NULL,
  contract_id uuid NOT NULL,
  charge_id uuid,
  criterio text NOT NULL,
  confianca integer NOT NULL,
  divergencia_valor numeric,
  divergencia_classe text,
  valor_pipe numeric,
  valor_voomp numeric,
  data_pagamento date,
  origem text DEFAULT 'AUTOMATICO'::text NOT NULL,
  run_id uuid,
  observacao text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  created_by uuid,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_by uuid,
  cross_tenant boolean DEFAULT false NOT NULL
);

-- TABLES cobranca
CREATE TABLE IF NOT EXISTS cobranca.cobranca_casos (
  caso_id uuid DEFAULT gen_random_uuid() NOT NULL,
  tenant_id uuid NOT NULL,
  contract_id uuid NOT NULL,
  valor_total_aberto numeric NOT NULL,
  parcelas_vencidas integer NOT NULL,
  faixa_aging cobranca.faixa_aging NOT NULL,
  status cobranca.status_caso DEFAULT 'em_aberto'::cobranca.status_caso NOT NULL,
  responsavel text,
  data_abertura timestamp with time zone DEFAULT now() NOT NULL,
  data_ultima_interacao timestamp with time zone,
  data_encerramento timestamp with time zone,
  valor_revertido numeric,
  data_pagamento_revertido date,
  observacao_encerramento text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS cobranca.cobranca_interacoes (
  interacao_id uuid DEFAULT gen_random_uuid() NOT NULL,
  caso_id uuid NOT NULL,
  data_contato timestamp with time zone DEFAULT now() NOT NULL,
  canal cobranca.canal_contato NOT NULL,
  mensagem_enviada cobranca.mensagem_regime,
  houve_retorno boolean DEFAULT false NOT NULL,
  observacao text,
  operador text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS cobranca.cobranca_negociacoes (
  negociacao_id uuid DEFAULT gen_random_uuid() NOT NULL,
  caso_id uuid NOT NULL,
  valor_total_acordado numeric NOT NULL,
  valor_entrada numeric,
  parcelas_acordadas integer,
  valor_parcela_acordo numeric,
  data_acordo date DEFAULT CURRENT_DATE NOT NULL,
  data_primeiro_vencimento date,
  status cobranca.status_acordo DEFAULT 'em_andamento'::cobranca.status_acordo NOT NULL,
  observacao text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);

-- PRIMARY KEYS
ALTER TABLE unipds.tenants ADD CONSTRAINT tenants_pkey PRIMARY KEY (tenant_id);
ALTER TABLE unipds.products ADD CONSTRAINT products_pkey PRIMARY KEY (product_id);
ALTER TABLE unipds.fontes ADD CONSTRAINT fontes_pkey PRIMARY KEY (fonte_id);
ALTER TABLE unipds.students ADD CONSTRAINT students_pkey PRIMARY KEY (student_id);
ALTER TABLE unipds.contracts ADD CONSTRAINT contracts_pkey PRIMARY KEY (contract_id);
ALTER TABLE unipds.charges ADD CONSTRAINT charges_pkey PRIMARY KEY (charge_id);
ALTER TABLE unipds.previsao_parcelas ADD CONSTRAINT previsao_parcelas_pkey PRIMARY KEY (previsao_id);
ALTER TABLE unipds.payment_attempts ADD CONSTRAINT payment_attempts_pkey PRIMARY KEY (attempt_id);
ALTER TABLE unipds.refunds ADD CONSTRAINT refunds_pkey PRIMARY KEY (refund_id);
ALTER TABLE unipds.raw_imports ADD CONSTRAINT raw_imports_pkey PRIMARY KEY (import_id);
ALTER TABLE unipds.raw_lines ADD CONSTRAINT raw_lines_pkey PRIMARY KEY (line_id);
ALTER TABLE unipds.pipe_deals ADD CONSTRAINT pipe_deals_pkey PRIMARY KEY (tenant_id, pipe_deal_id);
ALTER TABLE unipds.fechamentos_mensais ADD CONSTRAINT fechamentos_mensais_pkey PRIMARY KEY (fechamento_id);
ALTER TABLE unipds.ingestao_status ADD CONSTRAINT ingestao_status_pkey PRIMARY KEY (ingestao_status_id);
ALTER TABLE unipds.conciliacao_runs ADD CONSTRAINT conciliacao_runs_pkey PRIMARY KEY (run_id);
ALTER TABLE unipds.conciliacao_links ADD CONSTRAINT conciliacao_links_pkey PRIMARY KEY (link_id);
ALTER TABLE cobranca.cobranca_casos ADD CONSTRAINT cobranca_casos_pkey PRIMARY KEY (caso_id);
ALTER TABLE cobranca.cobranca_interacoes ADD CONSTRAINT cobranca_interacoes_pkey PRIMARY KEY (interacao_id);
ALTER TABLE cobranca.cobranca_negociacoes ADD CONSTRAINT cobranca_negociacoes_pkey PRIMARY KEY (negociacao_id);

-- UNIQUE CONSTRAINTS
ALTER TABLE unipds.tenants ADD CONSTRAINT tenants_cnpj_key UNIQUE (cnpj);
ALTER TABLE unipds.products ADD CONSTRAINT products_tenant_id_voomp_produto_id_key UNIQUE (tenant_id, voomp_produto_id);
ALTER TABLE unipds.students ADD CONSTRAINT students_tenant_id_cpf_cnpj_key UNIQUE (tenant_id, cpf_cnpj);
ALTER TABLE unipds.contracts ADD CONSTRAINT contracts_tenant_id_contract_ref_key UNIQUE (tenant_id, contract_ref);
ALTER TABLE unipds.contracts ADD CONSTRAINT contracts_tenant_id_voomp_contrato_id_key UNIQUE (tenant_id, voomp_contrato_id);
ALTER TABLE unipds.charges ADD CONSTRAINT charges_voomp_venda_id_key UNIQUE (voomp_venda_id);
ALTER TABLE unipds.previsao_parcelas ADD CONSTRAINT previsao_parcelas_previsao_ref_key UNIQUE (previsao_ref);
ALTER TABLE unipds.payment_attempts ADD CONSTRAINT payment_attempts_voomp_venda_id_key UNIQUE (voomp_venda_id);
ALTER TABLE unipds.refunds ADD CONSTRAINT refunds_voomp_venda_id_key UNIQUE (voomp_venda_id);
ALTER TABLE unipds.raw_imports ADD CONSTRAINT raw_imports_fonte_id_sha256_hash_key UNIQUE (fonte_id, sha256_hash);
ALTER TABLE unipds.raw_lines ADD CONSTRAINT raw_lines_import_id_linha_numero_key UNIQUE (import_id, linha_numero);
ALTER TABLE unipds.fechamentos_mensais ADD CONSTRAINT fechamentos_mensais_unique UNIQUE (tenant_id, ano_mes);
ALTER TABLE unipds.ingestao_status ADD CONSTRAINT ingestao_status_unique UNIQUE (tenant_id, fonte_id, ano_mes);
ALTER TABLE unipds.conciliacao_links ADD CONSTRAINT conciliacao_links_contract_unique UNIQUE (contract_id);
ALTER TABLE unipds.conciliacao_links ADD CONSTRAINT conciliacao_links_pipe_unique UNIQUE (tenant_id, pipe_deal_id);
ALTER TABLE cobranca.cobranca_casos ADD CONSTRAINT uq_caso_por_contrato UNIQUE (contract_id);

-- FOREIGN KEYS
ALTER TABLE unipds.products ADD CONSTRAINT products_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES unipds.tenants (tenant_id);
ALTER TABLE unipds.fontes ADD CONSTRAINT fontes_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES unipds.tenants (tenant_id);
ALTER TABLE unipds.students ADD CONSTRAINT students_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES unipds.tenants (tenant_id);
ALTER TABLE unipds.contracts ADD CONSTRAINT contracts_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES unipds.tenants (tenant_id);
ALTER TABLE unipds.contracts ADD CONSTRAINT contracts_fonte_id_fkey FOREIGN KEY (fonte_id) REFERENCES unipds.fontes (fonte_id);
ALTER TABLE unipds.contracts ADD CONSTRAINT contracts_student_id_fkey FOREIGN KEY (student_id) REFERENCES unipds.students (student_id);
ALTER TABLE unipds.contracts ADD CONSTRAINT contracts_product_id_fkey FOREIGN KEY (product_id) REFERENCES unipds.products (product_id);
ALTER TABLE unipds.contracts ADD CONSTRAINT contracts_contrato_espelho_de_fkey FOREIGN KEY (contrato_espelho_de) REFERENCES unipds.contracts (contract_id);
ALTER TABLE unipds.charges ADD CONSTRAINT charges_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES unipds.contracts (contract_id);
ALTER TABLE unipds.previsao_parcelas ADD CONSTRAINT previsao_parcelas_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES unipds.contracts (contract_id);
ALTER TABLE unipds.previsao_parcelas ADD CONSTRAINT previsao_parcelas_charge_id_fkey FOREIGN KEY (charge_id) REFERENCES unipds.charges (charge_id);
ALTER TABLE unipds.payment_attempts ADD CONSTRAINT payment_attempts_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES unipds.contracts (contract_id);
ALTER TABLE unipds.refunds ADD CONSTRAINT refunds_charge_id_fkey FOREIGN KEY (charge_id) REFERENCES unipds.charges (charge_id);
ALTER TABLE unipds.raw_imports ADD CONSTRAINT raw_imports_fonte_id_fkey FOREIGN KEY (fonte_id) REFERENCES unipds.fontes (fonte_id);
ALTER TABLE unipds.raw_lines ADD CONSTRAINT raw_lines_import_id_fkey FOREIGN KEY (import_id) REFERENCES unipds.raw_imports (import_id);
ALTER TABLE unipds.pipe_deals ADD CONSTRAINT pipe_deals_tenant_fk FOREIGN KEY (tenant_id) REFERENCES unipds.tenants (tenant_id);
ALTER TABLE unipds.fechamentos_mensais ADD CONSTRAINT fechamentos_mensais_tenant_fk FOREIGN KEY (tenant_id) REFERENCES unipds.tenants (tenant_id);
ALTER TABLE unipds.ingestao_status ADD CONSTRAINT ingestao_status_tenant_fk FOREIGN KEY (tenant_id) REFERENCES unipds.tenants (tenant_id);
ALTER TABLE unipds.ingestao_status ADD CONSTRAINT ingestao_status_fonte_fk FOREIGN KEY (fonte_id) REFERENCES unipds.fontes (fonte_id);
ALTER TABLE unipds.ingestao_status ADD CONSTRAINT ingestao_status_import_fk FOREIGN KEY (ultimo_import_id) REFERENCES unipds.raw_imports (import_id);
ALTER TABLE unipds.conciliacao_runs ADD CONSTRAINT conciliacao_runs_tenant_fk FOREIGN KEY (tenant_id) REFERENCES unipds.tenants (tenant_id);
ALTER TABLE unipds.conciliacao_runs ADD CONSTRAINT conciliacao_runs_fechamento_fk FOREIGN KEY (fechamento_id) REFERENCES unipds.fechamentos_mensais (fechamento_id);
ALTER TABLE unipds.conciliacao_links ADD CONSTRAINT conciliacao_links_tenant_fk FOREIGN KEY (tenant_id) REFERENCES unipds.tenants (tenant_id);
ALTER TABLE unipds.conciliacao_links ADD CONSTRAINT conciliacao_links_contract_fk FOREIGN KEY (contract_id) REFERENCES unipds.contracts (contract_id) ON DELETE CASCADE;
ALTER TABLE unipds.conciliacao_links ADD CONSTRAINT conciliacao_links_charge_fk FOREIGN KEY (charge_id) REFERENCES unipds.charges (charge_id);
ALTER TABLE unipds.conciliacao_links ADD CONSTRAINT conciliacao_links_run_fk FOREIGN KEY (run_id) REFERENCES unipds.conciliacao_runs (run_id);
ALTER TABLE unipds.conciliacao_links ADD CONSTRAINT conciliacao_links_pipe_fk FOREIGN KEY (tenant_id, pipe_deal_id) REFERENCES unipds.pipe_deals (tenant_id, pipe_deal_id) ON DELETE CASCADE;
ALTER TABLE cobranca.cobranca_casos ADD CONSTRAINT cobranca_casos_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES unipds.contracts (contract_id);
ALTER TABLE cobranca.cobranca_interacoes ADD CONSTRAINT cobranca_interacoes_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES cobranca.cobranca_casos (caso_id);
ALTER TABLE cobranca.cobranca_negociacoes ADD CONSTRAINT cobranca_negociacoes_caso_id_fkey FOREIGN KEY (caso_id) REFERENCES cobranca.cobranca_casos (caso_id);

-- INDEXES
CREATE INDEX idx_casos_faixa ON cobranca.cobranca_casos USING btree (faixa_aging);
CREATE INDEX idx_casos_status ON cobranca.cobranca_casos USING btree (status);
CREATE INDEX idx_casos_tenant ON cobranca.cobranca_casos USING btree (tenant_id);
CREATE INDEX idx_interacoes_caso ON cobranca.cobranca_interacoes USING btree (caso_id);
CREATE INDEX idx_negociacoes_caso ON cobranca.cobranca_negociacoes USING btree (caso_id);
CREATE INDEX idx_charges_atraso ON unipds.charges USING btree (dias_atraso) WHERE (dias_atraso > 0);
CREATE INDEX idx_charges_contract ON unipds.charges USING btree (contract_id);
CREATE INDEX idx_charges_status ON unipds.charges USING btree (status);
CREATE INDEX idx_charges_vencimento ON unipds.charges USING btree (data_vencimento) WHERE (status = 'Aguardando Pagamento'::text);
CREATE INDEX idx_links_divergencia_classe ON unipds.conciliacao_links USING btree (tenant_id, ano_mes, divergencia_classe) WHERE (divergencia_classe = ANY (ARRAY['CUPOM_PROVAVEL'::text, 'MATERIAL'::text]));
CREATE INDEX idx_links_run ON unipds.conciliacao_links USING btree (run_id);
CREATE INDEX idx_links_tenant_anomes ON unipds.conciliacao_links USING btree (tenant_id, ano_mes);
CREATE INDEX idx_runs_tenant_anomes ON unipds.conciliacao_runs USING btree (tenant_id, ano_mes, iniciado_em DESC);
CREATE INDEX idx_contracts_data ON unipds.contracts USING btree (tenant_id, data_primeira_venda);
CREATE INDEX idx_contracts_product ON unipds.contracts USING btree (product_id);
CREATE INDEX idx_contracts_status ON unipds.contracts USING btree (tenant_id, status_contrato);
CREATE INDEX idx_contracts_student ON unipds.contracts USING btree (student_id);
CREATE INDEX idx_contracts_voomp_id ON unipds.contracts USING btree (voomp_contrato_id) WHERE (voomp_contrato_id IS NOT NULL);
CREATE INDEX idx_fechamentos_tenant_estado ON unipds.fechamentos_mensais USING btree (tenant_id, estado);
CREATE INDEX idx_ingestao_status_tenant_anomes ON unipds.ingestao_status USING btree (tenant_id, ano_mes, status);
CREATE INDEX idx_attempts_contract ON unipds.payment_attempts USING btree (contract_id);
CREATE INDEX idx_pipe_deals_cpf_clean ON unipds.pipe_deals USING btree (tenant_id, cpf_clean) WHERE (cpf_clean IS NOT NULL);
CREATE INDEX idx_pipe_deals_email_clean ON unipds.pipe_deals USING btree (tenant_id, email_clean) WHERE (email_clean IS NOT NULL);
CREATE INDEX idx_pipe_deals_status ON unipds.pipe_deals USING btree (tenant_id, status);
CREATE INDEX idx_pipe_deals_telefone_clean ON unipds.pipe_deals USING btree (tenant_id, telefone_clean) WHERE (telefone_clean IS NOT NULL);
CREATE INDEX idx_pipe_deals_tenant_anomes ON unipds.pipe_deals USING btree (tenant_id, ano_mes);
CREATE INDEX idx_previsao_contract ON unipds.previsao_parcelas USING btree (contract_id);
CREATE INDEX idx_previsao_data ON unipds.previsao_parcelas USING btree (data_prevista) WHERE (status = 'previsto'::text);
CREATE INDEX idx_previsao_status ON unipds.previsao_parcelas USING btree (tenant_id, status);
CREATE INDEX idx_raw_lines_import ON unipds.raw_lines USING btree (import_id, status);
CREATE INDEX idx_raw_lines_payload ON unipds.raw_lines USING gin (payload);
CREATE INDEX idx_refunds_charge ON unipds.refunds USING btree (charge_id);
CREATE INDEX idx_refunds_tipo ON unipds.refunds USING btree (tipo);
CREATE INDEX idx_students_tenant_cpf ON unipds.students USING btree (tenant_id, cpf_cnpj);
CREATE INDEX idx_students_tenant_email ON unipds.students USING btree (tenant_id, email);

-- FUNCTIONS unipds
CREATE OR REPLACE FUNCTION unipds.set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at = NOW(); RETURN NEW; END; $$;
CREATE OR REPLACE FUNCTION unipds.tg_set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;
CREATE OR REPLACE FUNCTION unipds.atualizar_dias_atraso() RETURNS void LANGUAGE sql AS $$ UPDATE unipds.charges SET dias_atraso = CASE WHEN status = 'Aguardando Pagamento' AND data_vencimento < CURRENT_DATE THEN (CURRENT_DATE - data_vencimento) ELSE 0 END WHERE status = 'Aguardando Pagamento'; $$;
CREATE OR REPLACE FUNCTION unipds.gerar_contract_ref(p_fonte_id uuid, p_voomp_venda_id text, p_voomp_contrato_id text DEFAULT NULL::text) RETURNS text LANGUAGE plpgsql AS $$ BEGIN IF p_voomp_contrato_id IS NOT NULL THEN RETURN 'VMP-' || p_voomp_contrato_id; ELSE RETURN 'UNP-' || UPPER(LEFT(p_fonte_id::TEXT, 8)) || '-' || p_voomp_venda_id; END IF; END; $$;
CREATE OR REPLACE FUNCTION unipds.get_parcelas_vencidas(p_contract_id uuid) RETURNS TABLE(previsao_id uuid, previsao_ref text, numero_parcela integer, total_parcelas integer, valor_previsto numeric, data_prevista date, status text) LANGUAGE sql SECURITY DEFINER SET search_path TO 'unipds' AS $$ SELECT previsao_id, previsao_ref, numero_parcela, total_parcelas, valor_previsto, data_prevista, status FROM unipds.previsao_parcelas WHERE contract_id = p_contract_id AND status = 'vencido' ORDER BY data_prevista ASC; $$;

CREATE OR REPLACE FUNCTION unipds.gerar_previsao_parcelas(p_contract_id uuid)
RETURNS integer LANGUAGE plpgsql AS $func$
DECLARE
    v_contract RECORD; v_data_base DATE; v_data_p1 DATE; v_valor_p1 NUMERIC(12,2);
    i INT; v_inseridos INT := 0; v_ref TEXT; v_charge_id UUID;
    v_valor_previsto NUMERIC(12,2); v_data_pag DATE; v_status TEXT;
BEGIN
    SELECT ch.data_pagamento, COALESCE(ch.valor_oferta_linha, ch.faturamento_total, ch.valor_cobrado)
    INTO v_data_p1, v_valor_p1 FROM unipds.charges ch
    WHERE ch.contract_id = p_contract_id AND ch.numero_parcela = 1 AND ch.status = 'Pago' AND ch.valor_cobrado > 0 LIMIT 1;
    SELECT * INTO v_contract FROM unipds.contracts WHERE contract_id = p_contract_id;
    v_data_base := COALESCE(v_data_p1, v_contract.data_primeira_venda);
    v_valor_p1 := COALESCE(v_valor_p1, v_contract.valor_oferta);
    IF v_valor_p1 IS NULL OR v_valor_p1 = 0 THEN v_valor_p1 := v_contract.valor_oferta; END IF;
    FOR i IN 1..COALESCE(v_contract.recorrencia_total, 12) LOOP
        v_ref := 'PRV-' || v_contract.contract_ref || '-P' || LPAD(i::TEXT, 2, '0');
        SELECT ch.charge_id, ch.data_pagamento, COALESCE(ch.valor_oferta_linha, ch.faturamento_total, ch.valor_cobrado)
        INTO v_charge_id, v_data_pag, v_valor_previsto FROM unipds.charges ch
        WHERE ch.contract_id = p_contract_id AND ch.numero_parcela = i AND ch.status = 'Pago' AND ch.valor_cobrado > 0 LIMIT 1;
        IF v_charge_id IS NULL THEN
            v_valor_previsto := v_valor_p1; v_data_pag := NULL;
            v_status := CASE WHEN (v_data_base + ((i-1) || ' months')::INTERVAL) < CURRENT_DATE THEN 'vencido' ELSE 'previsto' END;
        ELSE
            v_status := 'pago';
            IF v_valor_previsto IS NULL OR v_valor_previsto = 0 THEN v_valor_previsto := v_valor_p1; END IF;
        END IF;
        INSERT INTO unipds.previsao_parcelas (contract_id, tenant_id, numero_parcela, total_parcelas, previsao_ref, valor_previsto, data_prevista, data_pagamento, charge_id, status)
        VALUES (p_contract_id, v_contract.tenant_id, i, COALESCE(v_contract.recorrencia_total, 12), v_ref, v_valor_previsto, v_data_base + ((i-1) || ' months')::INTERVAL, v_data_pag, v_charge_id, v_status)
        ON CONFLICT (previsao_ref) DO NOTHING;
        v_inseridos := v_inseridos + 1;
    END LOOP;
    RETURN v_inseridos;
END; $func$;

CREATE OR REPLACE FUNCTION unipds.tg_validar_ingestao_antes_fechamento()
RETURNS trigger LANGUAGE plpgsql SET search_path TO '' AS $func$
DECLARE v_fontes_ativas integer; v_fontes_completas integer;
BEGIN
    IF NEW.estado IN ('EM_REVISAO','FECHADO') AND (TG_OP = 'INSERT' OR OLD.estado IS DISTINCT FROM NEW.estado) THEN
        SELECT COUNT(*) INTO v_fontes_ativas FROM unipds.fontes WHERE tenant_id = NEW.tenant_id AND ativo = true;
        SELECT COUNT(*) INTO v_fontes_completas FROM unipds.ingestao_status ist JOIN unipds.fontes f ON f.fonte_id = ist.fonte_id
        WHERE ist.tenant_id = NEW.tenant_id AND ist.ano_mes = NEW.ano_mes AND ist.status = 'COMPLETA' AND f.ativo = true;
        IF v_fontes_completas < v_fontes_ativas THEN
            RAISE EXCEPTION 'Bloqueado: ingestao incompleta. Fontes ativas: %, COMPLETA para %: %.', v_fontes_ativas, NEW.ano_mes, v_fontes_completas;
        END IF;
        IF NEW.ingestao_validada_em IS NULL THEN NEW.ingestao_validada_em := now(); END IF;
    END IF;
    RETURN NEW;
END; $func$;

-- FUNCTIONS cobranca
CREATE OR REPLACE FUNCTION cobranca.set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at = NOW(); RETURN NEW; END; $$;
CREATE OR REPLACE FUNCTION cobranca.registrar_encerramento() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.status IN ('pago','baixado','extrajudicial') AND OLD.status NOT IN ('pago','baixado','extrajudicial') THEN NEW.data_encerramento = NOW(); END IF; RETURN NEW; END; $$;
CREATE OR REPLACE FUNCTION cobranca.atualizar_ultima_interacao() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN UPDATE cobranca.cobranca_casos SET data_ultima_interacao = NOW() WHERE caso_id = NEW.caso_id; RETURN NEW; END; $$;

-- VIEWS
CREATE OR REPLACE VIEW unipds.v_produtos_classificados AS
 SELECT product_id, voomp_produto_id, nome, tipo,
    CASE
        WHEN voomp_produto_id = ANY (ARRAY['7724','7852','13761','13762','12663','11957','11971','12657','12658','12882','13459','13764','13766']) THEN 'POS_GRADUACAO'
        WHEN voomp_produto_id = ANY (ARRAY['7725','7856','11973','11974','13497','14164']) THEN 'EXTENSAO'
        WHEN voomp_produto_id = ANY (ARRAY['9752','12228','10908','11972']) THEN 'ADMINISTRATIVO'
        ELSE 'OUTRO'
    END AS classe
   FROM unipds.products;

CREATE OR REPLACE VIEW unipds.v_cobracas_reais AS
 SELECT ch.charge_id, ch.contract_id, ch.voomp_venda_id, ch.numero_parcela, ch.forma_pagamento,
    ch.valor_cobrado, ch.faturamento_total, ch.valor_oferta_linha, ch.taxa_voomp, ch.comissao_coprodutor,
    ch.valor_recebido, ch.metodo_pagamento, ch.status, ch.data_vencimento, ch.data_pagamento,
    ch.data_liberacao_saldo, ch.dias_atraso, ch.link_boleto, ch.chave_pix, ch.nota_fiscal, ch.cupom, ch.created_at,
    c.tenant_id, c.student_id, c.product_id, c.tipo_cobranca, c.status_contrato, c.contract_ref, c.contrato_canonico
   FROM unipds.charges ch JOIN unipds.contracts c ON c.contract_id = ch.contract_id
  WHERE ch.valor_cobrado > 0 AND c.contrato_canonico = true
    AND c.status_contrato <> ALL (ARRAY['failed','Recusado']) AND ch.status <> 'Recusado';

CREATE OR REPLACE VIEW unipds.v_evasao AS
 SELECT ch.charge_id, ch.status, ch.numero_parcela, ch.metodo_pagamento, ch.valor_cobrado, ch.valor_recebido,
    ch.data_pagamento, co.contract_ref, co.nome_oferta, co.tipo_cobranca, co.recorrencia_total,
    co.data_primeira_venda, co.tenant_id, s.nome, s.cpf_cnpj, t.nome AS tenant_nome
   FROM unipds.charges ch
     JOIN unipds.contracts co ON co.contract_id = ch.contract_id
     JOIN unipds.students s ON s.student_id = co.student_id
     JOIN unipds.tenants t ON t.tenant_id = co.tenant_id
  WHERE ch.status = ANY (ARRAY['Reembolsado','Reembolso Pendente','Chargeback']);

CREATE OR REPLACE VIEW unipds.v_novos_alunos_voomp AS
 WITH ppp AS (
     SELECT DISTINCT ON (ch.contract_id) ch.contract_id, ch.charge_id, ch.voomp_venda_id,
        ch.valor_recebido, ch.valor_cobrado, ch.data_pagamento, ch.metodo_pagamento, ch.status AS charge_status
       FROM unipds.charges ch
      WHERE ch.status = ANY (ARRAY['Pago','Reembolsado']) AND COALESCE(ch.numero_parcela,1) = 1 AND ch.data_pagamento IS NOT NULL
      ORDER BY ch.contract_id, CASE ch.status WHEN 'Pago' THEN 0 ELSE 1 END, ch.data_pagamento)
 SELECT c.tenant_id, c.contract_id, c.fonte_id, f.nome AS fonte_nome, c.contract_ref, c.voomp_contrato_id,
    ppp.voomp_venda_id AS voomp_venda_id_primeira_parcela, c.tipo_cobranca, c.recorrencia_total, c.valor_oferta,
    CASE WHEN c.tipo_cobranca='Assinatura' AND c.recorrencia_total IS NOT NULL THEN c.valor_oferta*c.recorrencia_total ELSE c.valor_oferta END AS valor_contrato_total,
    CASE WHEN c.tipo_cobranca='Assinatura' AND c.recorrencia_total IS NOT NULL THEN ppp.valor_recebido*c.recorrencia_total ELSE ppp.valor_recebido END AS valor_recebido_total,
    c.status_contrato, c.data_primeira_venda, c.contrato_canonico,
    ppp.charge_id, ppp.valor_recebido, ppp.valor_cobrado, ppp.data_pagamento, ppp.metodo_pagamento,
    to_char(ppp.data_pagamento::timestamptz,'YYYY-MM') AS ano_mes,
    s.student_id, s.cpf_cnpj,
    regexp_replace(COALESCE(s.cpf_cnpj,''),'\D','','g') AS cpf_clean,
    lower(trim(s.email)) AS email_clean, s.nome AS aluno_nome,
    lower(translate(regexp_replace(COALESCE(s.nome,''),'[^[:alpha:][:space:]]','','g'),'áéíóúàèìòùâêîôûãõçÁÉÍÓÚÀÈÌÒÙÂÊÎÔÛÃÕÇ','aeiouaeiouaeiouaocaeiouaeiouaeiouaoc')) AS aluno_nome_norm,
    regexp_replace(COALESCE(s.telefone,''),'\D','','g') AS telefone_clean,
    p.nome AS produto_nome, c.nome_oferta,
    CASE WHEN c.tipo_cobranca='Assinatura' AND c.recorrencia_total IS NOT NULL THEN ppp.valor_cobrado*c.recorrencia_total ELSE ppp.valor_cobrado END AS valor_cobrado_total,
    (ppp.charge_status='Reembolsado') AS reembolsado
   FROM unipds.contracts c
     JOIN unipds.fontes f ON f.fonte_id=c.fonte_id
     JOIN unipds.students s ON s.student_id=c.student_id
     LEFT JOIN unipds.products p ON p.product_id=c.product_id
     JOIN ppp ON ppp.contract_id=c.contract_id
  WHERE c.contrato_canonico=true;

CREATE OR REPLACE VIEW unipds.v_inadimplencia AS
 SELECT s.student_id, s.nome, s.cpf_cnpj, s.email, s.telefone,
    c.contract_ref, c.tipo_cobranca, c.status_contrato, p.classe AS tipo_curso,
    pp.previsao_id, pp.previsao_ref, pp.numero_parcela, pp.total_parcelas,
    pp.valor_previsto AS valor_devido, pp.data_prevista AS data_vencimento,
    (CURRENT_DATE - pp.data_prevista) AS dias_atraso,
    CASE WHEN (CURRENT_DATE-pp.data_prevista) BETWEEN 1 AND 30 THEN '1-30 dias'
         WHEN (CURRENT_DATE-pp.data_prevista) BETWEEN 31 AND 60 THEN '31-60 dias'
         WHEN (CURRENT_DATE-pp.data_prevista) BETWEEN 61 AND 90 THEN '61-90 dias'
         WHEN (CURRENT_DATE-pp.data_prevista) > 90 THEN '+90 dias' ELSE NULL END AS faixa_atraso,
    pp.tenant_id,
    CASE pp.tenant_id WHEN '70b668e4-be85-459b-8dbb-3876929ac850'::uuid THEN 'Java' WHEN 'e717e24d-fb30-4ed0-83d3-bb8ea0b66783'::uuid THEN 'IA' ELSE NULL END AS tenant_nome
   FROM unipds.previsao_parcelas pp
     JOIN unipds.contracts c ON c.contract_id=pp.contract_id
     JOIN unipds.students s ON s.student_id=c.student_id
     JOIN unipds.v_produtos_classificados p ON p.product_id=c.product_id
  WHERE pp.status='vencido' AND c.contrato_canonico=true AND c.status_contrato<>'Cancelado'
    AND p.classe<>'ADMINISTRATIVO'
    AND EXISTS (SELECT 1 FROM unipds.charges ch WHERE ch.contract_id=c.contract_id AND ch.status='Pago' AND COALESCE(ch.numero_parcela,1)=1)
  ORDER BY (CURRENT_DATE-pp.data_prevista) DESC;

CREATE OR REPLACE VIEW unipds.v_contas_a_receber AS
 SELECT s.nome, s.cpf_cnpj, s.email, s.telefone, c.contract_ref, c.voomp_contrato_id,
    c.tipo_cobranca, c.status_contrato, p.classe AS tipo_curso, pp.previsao_ref,
    pp.numero_parcela, pp.total_parcelas, pp.valor_previsto, pp.data_prevista,
    pp.status AS status_previsao, pp.data_pagamento AS data_confirmacao, pp.tenant_id,
    CASE pp.tenant_id WHEN '70b668e4-be85-459b-8dbb-3876929ac850'::uuid THEN 'Java' WHEN 'e717e24d-fb30-4ed0-83d3-bb8ea0b66783'::uuid THEN 'IA' ELSE NULL END AS tenant_nome
   FROM unipds.previsao_parcelas pp
     JOIN unipds.contracts c ON c.contract_id=pp.contract_id
     JOIN unipds.students s ON s.student_id=c.student_id
     JOIN unipds.v_produtos_classificados p ON p.product_id=c.product_id
  WHERE pp.status=ANY(ARRAY['previsto','vencido','pago']) AND c.contrato_canonico=true
    AND c.status_contrato<>'Cancelado' AND p.classe<>'ADMINISTRATIVO'
    AND EXISTS (SELECT 1 FROM unipds.charges ch WHERE ch.contract_id=c.contract_id AND ch.status='Pago' AND COALESCE(ch.numero_parcela,1)=1)
  ORDER BY pp.tenant_id, pp.data_prevista;

CREATE OR REPLACE VIEW unipds.v_matriculas_assinatura AS
 WITH pp AS (SELECT c.contract_id,c.student_id,c.product_id,c.contract_ref,c.voomp_contrato_id,c.recorrencia_total,c.status_contrato,c.tenant_id,min(ch.numero_parcela) AS primeira_parcela_paga,max(ch.numero_parcela) AS ultima_parcela_paga,count(ch.charge_id) AS parcelas_pagas_count,max(ch.data_pagamento) AS data_ultimo_pagamento,min(ch.data_pagamento) AS data_primeira_pagamento FROM unipds.contracts c JOIN unipds.charges ch ON ch.contract_id=c.contract_id WHERE c.tipo_cobranca='Assinatura' AND c.contrato_canonico=true AND ch.status='Pago' AND ch.valor_cobrado>0 GROUP BY c.contract_id,c.student_id,c.product_id,c.contract_ref,c.voomp_contrato_id,c.recorrencia_total,c.status_contrato,c.tenant_id)
 SELECT s.student_id,s.cpf_cnpj,s.nome,s.email,s.telefone,s.uf_origem,pp.contract_id,pp.contract_ref,pp.tenant_id,p.classe AS tipo_curso,p.nome AS produto_nome,pp.primeira_parcela_paga,pp.ultima_parcela_paga,pp.parcelas_pagas_count,pp.recorrencia_total AS total_parcelas_contrato,pp.data_primeira_pagamento AS data_matricula,pp.data_ultimo_pagamento,'ASSINATURA' AS modalidade,pp.status_contrato,CASE WHEN pp.primeira_parcela_paga>1 THEN true ELSE false END AS anomalia_sem_p1,CASE WHEN pp.recorrencia_total=10 THEN true ELSE false END AS anomalia_rec_10
   FROM pp JOIN unipds.students s ON s.student_id=pp.student_id JOIN unipds.v_produtos_classificados p ON p.product_id=pp.product_id WHERE p.classe<>'ADMINISTRATIVO';

CREATE OR REPLACE VIEW unipds.v_matriculas_unico AS
 SELECT s.student_id,s.cpf_cnpj,s.nome,s.email,s.telefone,s.uf_origem,c.contract_id,c.contract_ref,c.tenant_id,p.classe AS tipo_curso,p.nome AS produto_nome,ch.charge_id,ch.valor_cobrado,ch.metodo_pagamento,ch.data_pagamento AS data_matricula,'UNICO' AS modalidade,NULL::integer AS parcela_atual,NULL::integer AS total_parcelas,c.status_contrato
   FROM unipds.contracts c JOIN unipds.students s ON s.student_id=c.student_id JOIN unipds.charges ch ON ch.contract_id=c.contract_id JOIN unipds.v_produtos_classificados p ON p.product_id=c.product_id
  WHERE c.tipo_cobranca='Único' AND ch.status='Pago' AND ch.valor_cobrado>0 AND p.classe<>'ADMINISTRATIVO' AND c.contrato_canonico=true;

CREATE OR REPLACE VIEW unipds.v_matriculas_ativas AS
 SELECT student_id,cpf_cnpj,nome,email,telefone,uf_origem,contract_id,contract_ref,tenant_id,tipo_curso,produto_nome,modalidade,data_matricula,status_contrato,false AS anomalia_sem_p1,false AS anomalia_rec_10 FROM unipds.v_matriculas_unico
UNION ALL
 SELECT student_id,cpf_cnpj,nome,email,telefone,uf_origem,contract_id,contract_ref,tenant_id,tipo_curso,produto_nome,modalidade,data_matricula,status_contrato,anomalia_sem_p1,anomalia_rec_10 FROM unipds.v_matriculas_assinatura;

CREATE OR REPLACE VIEW unipds.v_resumo_executivo AS
 SELECT CASE WHEN tenant_id='70b668e4-be85-459b-8dbb-3876929ac850'::uuid THEN 'Java' WHEN tenant_id='e717e24d-fb30-4ed0-83d3-bb8ea0b66783'::uuid THEN 'IA' ELSE NULL END AS tenant,tipo_curso,modalidade,count(DISTINCT student_id) AS alunos_ativos,count(DISTINCT contract_id) AS contratos_ativos
   FROM unipds.v_matriculas_ativas GROUP BY tenant_id,tipo_curso,modalidade ORDER BY tenant,tipo_curso,modalidade;

CREATE OR REPLACE VIEW unipds.v_cruzamento_pipe AS
 SELECT pd.tenant_id,pd.ano_mes,pd.pipe_deal_id,pd.titulo,pd.funil,pd.proprietario,pd.pessoa_nome,pd.cpf_clean AS pipe_cpf_clean,pd.email_clean AS pipe_email_clean,pd.valor AS pipe_valor,pd.ganho_em AS pipe_ganho_em,cl.link_id,cl.criterio,cl.confianca,cl.divergencia_valor,cl.divergencia_classe,cl.cross_tenant,cl.contract_id,cl.charge_id,vna.contract_ref,vna.voomp_venda_id_primeira_parcela,vna.valor_recebido_total AS voomp_valor_contrato,vna.valor_oferta AS voomp_valor_oferta_parcela,vna.valor_contrato_total AS voomp_valor_contrato_bruto,vna.tipo_cobranca,vna.recorrencia_total,vna.valor_recebido AS voomp_valor_recebido_1a_parcela,vna.data_pagamento AS voomp_data_pagamento,vna.aluno_nome AS voomp_aluno_nome,vna.cpf_cnpj AS voomp_cpf,vna.tenant_id AS voomp_tenant_id,CASE WHEN cl.link_id IS NULL THEN 'ORFAO_PIPE' ELSE 'CASADO' END AS status_match,CASE WHEN cl.link_id IS NULL THEN 'SIM' ELSE 'NAO' END AS pendente_financeiro,vna.valor_cobrado_total AS voomp_valor_cobrado_total,vna.reembolsado AS voomp_reembolsado
   FROM unipds.pipe_deals pd LEFT JOIN unipds.conciliacao_links cl ON cl.tenant_id=pd.tenant_id AND cl.pipe_deal_id=pd.pipe_deal_id LEFT JOIN unipds.v_novos_alunos_voomp vna ON vna.contract_id=cl.contract_id WHERE pd.status='Ganho';

CREATE OR REPLACE VIEW unipds.v_cruzamento_voomp AS
 SELECT vna.tenant_id,vna.ano_mes,vna.contract_id,vna.contract_ref,vna.voomp_contrato_id,vna.voomp_venda_id_primeira_parcela,vna.tipo_cobranca,vna.recorrencia_total,vna.aluno_nome,vna.cpf_cnpj,vna.email_clean,vna.fonte_nome,vna.produto_nome,vna.valor_oferta AS voomp_valor_oferta_parcela,vna.valor_recebido_total AS voomp_valor_contrato,vna.valor_contrato_total AS voomp_valor_contrato_bruto,vna.valor_recebido AS voomp_valor_recebido_1a_parcela,vna.data_pagamento,vna.metodo_pagamento,cl.link_id,cl.pipe_deal_id,cl.criterio,cl.confianca,cl.divergencia_valor,cl.divergencia_classe,cl.cross_tenant,cl.tenant_id AS pipe_tenant_id,pd.titulo AS pipe_titulo,pd.proprietario AS pipe_proprietario,pd.valor AS pipe_valor,pd.ganho_em AS pipe_ganho_em,CASE WHEN cl.link_id IS NULL THEN 'ORFAO_VOOMP' ELSE 'CASADO' END AS status_match,CASE WHEN cl.link_id IS NULL THEN 'SIM' ELSE 'NAO' END AS venda_orfa,vna.valor_cobrado_total AS voomp_valor_cobrado_total,vna.reembolsado AS voomp_reembolsado
   FROM unipds.v_novos_alunos_voomp vna LEFT JOIN unipds.conciliacao_links cl ON cl.contract_id=vna.contract_id LEFT JOIN unipds.pipe_deals pd ON pd.tenant_id=cl.tenant_id AND pd.pipe_deal_id=cl.pipe_deal_id;

CREATE OR REPLACE VIEW unipds.v_suspeitos_tenant_errado AS
 WITH op AS (SELECT pd.tenant_id,pd.ano_mes,pd.pipe_deal_id,pd.pessoa_nome,pd.cpf_clean,pd.email_clean,pd.valor AS pipe_valor,pd.funil FROM unipds.pipe_deals pd WHERE pd.status='Ganho' AND NOT EXISTS(SELECT 1 FROM unipds.conciliacao_links cl WHERE cl.tenant_id=pd.tenant_id AND cl.pipe_deal_id=pd.pipe_deal_id)),
 ov AS (SELECT vna.tenant_id,vna.ano_mes,vna.contract_id,vna.aluno_nome,vna.cpf_clean,vna.email_clean,vna.valor_recebido_total AS voomp_valor FROM unipds.v_novos_alunos_voomp vna WHERE NOT EXISTS(SELECT 1 FROM unipds.conciliacao_links cl WHERE cl.contract_id=vna.contract_id)),
 n AS (SELECT op.ano_mes,op.tenant_id AS tenant_pipe,ov.tenant_id AS tenant_voomp,op.pipe_deal_id,op.funil,op.pessoa_nome AS pipe_nome,ov.aluno_nome AS voomp_nome,op.pipe_valor,ov.voomp_valor,op.cpf_clean AS pipe_cpf,ov.cpf_clean AS voomp_cpf,op.email_clean AS pipe_email,ov.email_clean AS voomp_email,ov.contract_id AS voomp_contract_id,lower(translate(regexp_replace(COALESCE(op.pessoa_nome,''),'[^[:alpha:][:space:]]','','g'),'áéíóúàèìòùâêîôûãõçÁÉÍÓÚÀÈÌÒÙÂÊÎÔÛÃÕÇ','aeiouaeiouaeiouaocaeiouaeiouaeiouaoc')) AS pipe_nome_norm,lower(translate(regexp_replace(COALESCE(ov.aluno_nome,''),'[^[:alpha:][:space:]]','','g'),'áéíóúàèìòùâêîôûãõçÁÉÍÓÚÀÈÌÒÙÂÊÎÔÛÃÕÇ','aeiouaeiouaeiouaocaeiouaeiouaeiouaoc')) AS voomp_nome_norm FROM op JOIN ov ON op.ano_mes=ov.ano_mes AND op.tenant_id<>ov.tenant_id AND ((op.cpf_clean<>'' AND op.cpf_clean=ov.cpf_clean) OR (op.email_clean<>'' AND op.email_clean=ov.email_clean)))
 SELECT ano_mes,tenant_pipe,tenant_voomp,pipe_deal_id,funil,pipe_nome,voomp_nome,pipe_valor,voomp_valor,CASE WHEN pipe_cpf<>'' AND pipe_cpf=voomp_cpf THEN 'CPF' ELSE 'EMAIL' END AS criterio_suspeita,round(similarity(pipe_nome_norm,voomp_nome_norm)*100)::integer AS similaridade_nome,voomp_contract_id FROM n;

CREATE OR REPLACE VIEW cobranca.v_casos_completos AS
 SELECT cc.caso_id,cc.contract_id,cc.tenant_id,CASE WHEN cc.tenant_id='70b668e4-be85-459b-8dbb-3876929ac850'::uuid THEN 'Java' WHEN cc.tenant_id='e717e24d-fb30-4ed0-83d3-bb8ea0b66783'::uuid THEN 'IA' ELSE NULL END AS tenant_nome,cc.status,cc.faixa_aging,cc.valor_total_aberto,cc.parcelas_vencidas,cc.valor_revertido,cc.data_pagamento_revertido,cc.responsavel,cc.data_abertura,cc.data_ultima_interacao,cc.data_encerramento,cc.observacao_encerramento,c.contract_ref,c.voomp_contrato_id,c.status_contrato,c.tipo_cobranca,s.nome,s.cpf_cnpj,s.email,s.telefone,(SELECT count(*) FROM cobranca.cobranca_interacoes ci WHERE ci.caso_id=cc.caso_id) AS total_contatos,(SELECT count(*) FROM cobranca.cobranca_interacoes ci WHERE ci.caso_id=cc.caso_id AND ci.houve_retorno=true) AS total_retornos,(SELECT max(ci.data_contato) FROM cobranca.cobranca_interacoes ci WHERE ci.caso_id=cc.caso_id) AS data_ultimo_contato,(SELECT cn.status FROM cobranca.cobranca_negociacoes cn WHERE cn.caso_id=cc.caso_id ORDER BY cn.created_at DESC LIMIT 1) AS status_negociacao,(SELECT cn.valor_total_acordado FROM cobranca.cobranca_negociacoes cn WHERE cn.caso_id=cc.caso_id ORDER BY cn.created_at DESC LIMIT 1) AS valor_negociado,(SELECT cn.data_primeiro_vencimento FROM cobranca.cobranca_negociacoes cn WHERE cn.caso_id=cc.caso_id ORDER BY cn.created_at DESC LIMIT 1) AS proximo_vencimento_acordo
   FROM cobranca.cobranca_casos cc JOIN unipds.contracts c ON c.contract_id=cc.contract_id JOIN unipds.students s ON s.student_id=c.student_id ORDER BY cc.faixa_aging DESC,cc.valor_total_aberto DESC;

CREATE OR REPLACE VIEW cobranca.v_kpis AS
 SELECT count(*) AS total_casos,count(*) FILTER(WHERE status='em_aberto'::cobranca.status_caso) AS casos_em_aberto,count(*) FILTER(WHERE status='em_contato'::cobranca.status_caso) AS casos_em_contato,count(*) FILTER(WHERE status IN('em_negociacao'::cobranca.status_caso,'acordo_ativo'::cobranca.status_caso)) AS casos_em_negociacao,count(*) FILTER(WHERE status='pago'::cobranca.status_caso) AS casos_revertidos,count(*) FILTER(WHERE status='extrajudicial'::cobranca.status_caso) AS casos_extrajudicial,count(*) FILTER(WHERE status='baixado'::cobranca.status_caso) AS casos_baixados,round(sum(valor_total_aberto),2) AS volume_carteira,round(sum(valor_revertido) FILTER(WHERE status='pago'::cobranca.status_caso),2) AS volume_revertido,round(sum(valor_revertido) FILTER(WHERE status='pago'::cobranca.status_caso)/NULLIF(sum(valor_total_aberto),0)*100,1) AS taxa_recuperacao_pct,(SELECT count(*) FROM cobranca.cobranca_interacoes) AS total_contatos,(SELECT count(*) FROM cobranca.cobranca_interacoes WHERE houve_retorno=true) AS total_retornos,(SELECT round(count(*) FILTER(WHERE houve_retorno=true)::numeric/NULLIF(count(*),0)::numeric*100,1) FROM cobranca.cobranca_interacoes) AS taxa_retorno_pct,(SELECT count(*) FROM cobranca.cobranca_negociacoes WHERE status='em_andamento'::cobranca.status_acordo) AS acordos_ativos,(SELECT round(sum(valor_total_acordado),2) FROM cobranca.cobranca_negociacoes WHERE status='em_andamento'::cobranca.status_acordo) AS volume_em_acordo,(SELECT round(sum(valor_total_acordado),2) FROM cobranca.cobranca_negociacoes WHERE status='cumprido'::cobranca.status_acordo) AS volume_acordos_cumpridos FROM cobranca.cobranca_casos;

-- TRIGGERS
CREATE TRIGGER trg_contracts_updated_at BEFORE UPDATE ON unipds.contracts FOR EACH ROW EXECUTE FUNCTION unipds.set_updated_at();
CREATE TRIGGER trg_products_updated_at BEFORE UPDATE ON unipds.products FOR EACH ROW EXECUTE FUNCTION unipds.set_updated_at();
CREATE TRIGGER trg_students_updated_at BEFORE UPDATE ON unipds.students FOR EACH ROW EXECUTE FUNCTION unipds.set_updated_at();
CREATE TRIGGER trg_previsao_updated_at BEFORE UPDATE ON unipds.previsao_parcelas FOR EACH ROW EXECUTE FUNCTION unipds.set_updated_at();
CREATE TRIGGER trg_links_updated_at BEFORE UPDATE ON unipds.conciliacao_links FOR EACH ROW EXECUTE FUNCTION unipds.tg_set_updated_at();
CREATE TRIGGER trg_fechamentos_updated_at BEFORE UPDATE ON unipds.fechamentos_mensais FOR EACH ROW EXECUTE FUNCTION unipds.tg_set_updated_at();
CREATE TRIGGER trg_pipe_deals_updated_at BEFORE UPDATE ON unipds.pipe_deals FOR EACH ROW EXECUTE FUNCTION unipds.tg_set_updated_at();
CREATE TRIGGER trg_ingestao_status_updated_at BEFORE UPDATE ON unipds.ingestao_status FOR EACH ROW EXECUTE FUNCTION unipds.tg_set_updated_at();
CREATE TRIGGER trg_validar_ingestao_fechamento BEFORE INSERT ON unipds.fechamentos_mensais FOR EACH ROW EXECUTE FUNCTION unipds.tg_validar_ingestao_antes_fechamento();
CREATE TRIGGER trg_validar_ingestao_fechamento BEFORE UPDATE ON unipds.fechamentos_mensais FOR EACH ROW EXECUTE FUNCTION unipds.tg_validar_ingestao_antes_fechamento();
CREATE TRIGGER trg_casos_encerramento BEFORE UPDATE ON cobranca.cobranca_casos FOR EACH ROW EXECUTE FUNCTION cobranca.registrar_encerramento();
CREATE TRIGGER trg_casos_updated_at BEFORE UPDATE ON cobranca.cobranca_casos FOR EACH ROW EXECUTE FUNCTION cobranca.set_updated_at();
CREATE TRIGGER trg_interacao_atualiza_caso AFTER INSERT ON cobranca.cobranca_interacoes FOR EACH ROW EXECUTE FUNCTION cobranca.atualizar_ultima_interacao();
CREATE TRIGGER trg_negociacoes_updated_at BEFORE UPDATE ON cobranca.cobranca_negociacoes FOR EACH ROW EXECUTE FUNCTION cobranca.set_updated_at();
