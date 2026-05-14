drop extension if exists "pg_net";

create schema if not exists "cobranca";

create schema if not exists "financeiro";

create schema if not exists "unipds";

create extension if not exists "pg_trgm" with schema "public";

create type "cobranca"."canal_contato" as enum ('whatsapp', 'telefone');

create type "cobranca"."faixa_aging" as enum ('faixa_1', 'faixa_2', 'faixa_3', 'faixa_4');

create type "cobranca"."mensagem_regime" as enum ('A', 'B', 'C', 'D', 'E', 'F', 'personalizada');

create type "cobranca"."status_acordo" as enum ('em_andamento', 'cumprido', 'quebrado');

create type "cobranca"."status_caso" as enum ('em_aberto', 'em_contato', 'em_negociacao', 'acordo_ativo', 'pago', 'extrajudicial', 'baixado');

create sequence "financeiro"."lancamentos_id_seq";

create sequence "financeiro"."mapeamento_categorias_id_seq";

create sequence "financeiro"."sync_log_id_seq";


  create table "cobranca"."cobranca_casos" (
    "caso_id" uuid not null default gen_random_uuid(),
    "tenant_id" uuid not null,
    "contract_id" uuid not null,
    "valor_total_aberto" numeric(12,2) not null,
    "parcelas_vencidas" integer not null,
    "faixa_aging" cobranca.faixa_aging not null,
    "status" cobranca.status_caso not null default 'em_aberto'::cobranca.status_caso,
    "responsavel" text,
    "data_abertura" timestamp with time zone not null default now(),
    "data_ultima_interacao" timestamp with time zone,
    "data_encerramento" timestamp with time zone,
    "valor_revertido" numeric(12,2),
    "data_pagamento_revertido" date,
    "observacao_encerramento" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "cobranca"."cobranca_casos" enable row level security;


  create table "cobranca"."cobranca_interacoes" (
    "interacao_id" uuid not null default gen_random_uuid(),
    "caso_id" uuid not null,
    "data_contato" timestamp with time zone not null default now(),
    "canal" cobranca.canal_contato not null,
    "mensagem_enviada" cobranca.mensagem_regime,
    "houve_retorno" boolean not null default false,
    "observacao" text,
    "operador" text not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "cobranca"."cobranca_interacoes" enable row level security;


  create table "cobranca"."cobranca_negociacoes" (
    "negociacao_id" uuid not null default gen_random_uuid(),
    "caso_id" uuid not null,
    "valor_total_acordado" numeric(12,2) not null,
    "valor_entrada" numeric(12,2),
    "parcelas_acordadas" integer,
    "valor_parcela_acordo" numeric(12,2),
    "data_acordo" date not null default CURRENT_DATE,
    "data_primeiro_vencimento" date,
    "status" cobranca.status_acordo not null default 'em_andamento'::cobranca.status_acordo,
    "observacao" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "cobranca"."cobranca_negociacoes" enable row level security;


  create table "financeiro"."lancamentos" (
    "id" bigint not null default nextval('financeiro.lancamentos_id_seq'::regclass),
    "id_omie" text not null,
    "empresa" text not null,
    "data" date not null,
    "valor" numeric(14,2) not null,
    "descricao" text,
    "categoria" text,
    "categoria_omie" text,
    "departamento" text,
    "conta_corrente" text,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone default now(),
    "numero_documento" text,
    "cod_integracao" text
      );


alter table "financeiro"."lancamentos" enable row level security;


  create table "financeiro"."mapeamento_categorias" (
    "id" bigint not null default nextval('financeiro.mapeamento_categorias_id_seq'::regclass),
    "codigo_omie" text not null,
    "nome_interno" text not null,
    "departamento" text not null default 'Geral'::text,
    "ativo" boolean default true,
    "created_at" timestamp with time zone default now(),
    "empresa" text not null default 'IA'::text
      );


alter table "financeiro"."mapeamento_categorias" enable row level security;


  create table "financeiro"."sync_log" (
    "id" bigint not null default nextval('financeiro.sync_log_id_seq'::regclass),
    "empresa" text not null,
    "periodo_inicio" date not null,
    "periodo_fim" date not null,
    "total_inseridos" integer default 0,
    "total_atualizados" integer default 0,
    "total_erros" integer default 0,
    "duracao_seg" numeric(8,2),
    "status" text default 'running'::text,
    "erro_msg" text,
    "executado_em" timestamp with time zone default now()
      );


alter table "financeiro"."sync_log" enable row level security;


  create table "unipds"."charges" (
    "charge_id" uuid not null default gen_random_uuid(),
    "contract_id" uuid not null,
    "voomp_venda_id" text not null,
    "numero_parcela" integer,
    "forma_pagamento" integer,
    "valor_cobrado" numeric(12,2) not null,
    "taxa_voomp" numeric(12,2),
    "comissao_coprodutor" numeric(12,2),
    "valor_recebido" numeric(12,2),
    "metodo_pagamento" text,
    "status" text not null,
    "data_vencimento" date,
    "data_pagamento" date,
    "data_liberacao_saldo" date,
    "dias_atraso" integer not null default 0,
    "link_boleto" text,
    "chave_pix" text,
    "nota_fiscal" text,
    "cupom" text,
    "created_at" timestamp with time zone not null default now(),
    "faturamento_total" numeric(12,2),
    "valor_oferta_linha" numeric(12,2)
      );


alter table "unipds"."charges" enable row level security;


  create table "unipds"."conciliacao_links" (
    "link_id" uuid not null default gen_random_uuid(),
    "tenant_id" uuid not null,
    "ano_mes" text not null,
    "pipe_deal_id" bigint not null,
    "contract_id" uuid not null,
    "charge_id" uuid,
    "criterio" text not null,
    "confianca" integer not null,
    "divergencia_valor" numeric(12,2),
    "divergencia_classe" text,
    "valor_pipe" numeric(12,2),
    "valor_voomp" numeric(12,2),
    "data_pagamento" date,
    "origem" text not null default 'AUTOMATICO'::text,
    "run_id" uuid,
    "observacao" text,
    "created_at" timestamp with time zone not null default now(),
    "created_by" uuid,
    "updated_at" timestamp with time zone not null default now(),
    "updated_by" uuid,
    "cross_tenant" boolean not null default false
      );


alter table "unipds"."conciliacao_links" enable row level security;


  create table "unipds"."conciliacao_runs" (
    "run_id" uuid not null default gen_random_uuid(),
    "tenant_id" uuid not null,
    "ano_mes" text not null,
    "fechamento_id" uuid,
    "iniciado_em" timestamp with time zone not null default now(),
    "finalizado_em" timestamp with time zone,
    "status" text not null default 'EM_EXECUCAO'::text,
    "total_pipe_avaliados" integer,
    "total_voomp_avaliados" integer,
    "matches_cpf" integer,
    "matches_email" integer,
    "matches_nome" integer,
    "matches_telefone" integer,
    "matches_manual" integer,
    "orfaos_pipe" integer,
    "orfaos_voomp" integer,
    "parametros" jsonb,
    "erro_msg" text,
    "executado_por" uuid
      );


alter table "unipds"."conciliacao_runs" enable row level security;


  create table "unipds"."contracts" (
    "contract_id" uuid not null default gen_random_uuid(),
    "tenant_id" uuid not null,
    "fonte_id" uuid not null,
    "student_id" uuid not null,
    "product_id" uuid not null,
    "voomp_contrato_id" text,
    "contract_ref" text not null,
    "voomp_oferta_id" text,
    "nome_oferta" text,
    "tipo_cobranca" text not null,
    "periodo" text,
    "recorrencia_total" integer,
    "valor_oferta" numeric(12,2) not null,
    "status_contrato" text not null,
    "data_primeira_venda" date,
    "data_encerramento" date,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now(),
    "contrato_canonico" boolean not null default true,
    "contrato_espelho_de" uuid
      );


alter table "unipds"."contracts" enable row level security;


  create table "unipds"."fechamentos_mensais" (
    "fechamento_id" uuid not null default gen_random_uuid(),
    "tenant_id" uuid not null,
    "ano_mes" text not null,
    "estado" text not null default 'ABERTO'::text,
    "total_pipe_deals" integer,
    "total_voomp_alunos" integer,
    "total_matches" integer,
    "total_orfaos_pipe" integer,
    "total_orfaos_voomp" integer,
    "hash_relatorio" text,
    "arquivo_relatorio_url" text,
    "fechado_em" timestamp with time zone,
    "fechado_por" uuid,
    "reaberto_em" timestamp with time zone,
    "reaberto_por" uuid,
    "motivo_reabertura" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now(),
    "ingestao_validada_em" timestamp with time zone,
    "ingestao_validada_por" uuid
      );


alter table "unipds"."fechamentos_mensais" enable row level security;


  create table "unipds"."fontes" (
    "fonte_id" uuid not null default gen_random_uuid(),
    "tenant_id" uuid not null,
    "nome" text not null,
    "plataforma" text not null default 'voomp'::text,
    "config" jsonb,
    "ativo" boolean not null default true,
    "created_at" timestamp with time zone not null default now()
      );


alter table "unipds"."fontes" enable row level security;


  create table "unipds"."ingestao_status" (
    "ingestao_status_id" uuid not null default gen_random_uuid(),
    "tenant_id" uuid not null,
    "fonte_id" uuid not null,
    "ano_mes" text not null,
    "status" text not null default 'PARCIAL'::text,
    "total_registros" integer,
    "ultimo_import_id" uuid,
    "confirmado_em" timestamp with time zone,
    "confirmado_por" uuid,
    "observacao" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "unipds"."ingestao_status" enable row level security;


  create table "unipds"."payment_attempts" (
    "attempt_id" uuid not null default gen_random_uuid(),
    "contract_id" uuid not null,
    "voomp_venda_id" text not null,
    "metodo_pagamento" text,
    "forma_pagamento" integer,
    "valor" numeric(12,2),
    "motivo_recusa" text,
    "tentativa_em" timestamp with time zone
      );


alter table "unipds"."payment_attempts" enable row level security;


  create table "unipds"."pipe_deals" (
    "pipe_deal_id" bigint not null,
    "tenant_id" uuid not null,
    "pessoa_id" bigint,
    "titulo" text not null,
    "valor" numeric(12,2) not null,
    "funil" text,
    "status" text not null,
    "ganho_em" timestamp with time zone,
    "data_perda" timestamp with time zone,
    "proprietario" text,
    "cpf_raw" text,
    "cpf_clean" text,
    "email_raw" text,
    "email_clean" text,
    "rg" text,
    "telefone_raw" text,
    "telefone_clean" text,
    "organizacao" text,
    "pessoa_nome" text,
    "pessoa_nome_norm" text,
    "ano_mes" text not null,
    "imported_at" timestamp with time zone not null default now(),
    "imported_by" uuid,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "unipds"."pipe_deals" enable row level security;


  create table "unipds"."previsao_parcelas" (
    "previsao_id" uuid not null default gen_random_uuid(),
    "contract_id" uuid not null,
    "tenant_id" uuid not null,
    "numero_parcela" integer not null,
    "total_parcelas" integer not null,
    "previsao_ref" text not null,
    "valor_previsto" numeric(12,2) not null,
    "data_prevista" date,
    "data_pagamento" date,
    "charge_id" uuid,
    "status" text not null default 'previsto'::text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "unipds"."previsao_parcelas" enable row level security;


  create table "unipds"."products" (
    "product_id" uuid not null default gen_random_uuid(),
    "tenant_id" uuid not null,
    "voomp_produto_id" text,
    "nome" text not null,
    "tipo" text,
    "categoria" text,
    "ativo" boolean not null default true,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "unipds"."products" enable row level security;


  create table "unipds"."raw_imports" (
    "import_id" uuid not null default gen_random_uuid(),
    "fonte_id" uuid not null,
    "nome_arquivo" text not null,
    "sha256_hash" text not null,
    "total_linhas" integer,
    "processadas" integer default 0,
    "erros" integer default 0,
    "status" text not null default 'pendente'::text,
    "imported_at" timestamp with time zone not null default now()
      );


alter table "unipds"."raw_imports" enable row level security;


  create table "unipds"."raw_lines" (
    "line_id" uuid not null default gen_random_uuid(),
    "import_id" uuid not null,
    "linha_numero" integer not null,
    "payload" jsonb not null,
    "status" text not null default 'pendente'::text,
    "erro_msg" text,
    "processed_at" timestamp with time zone
      );


alter table "unipds"."raw_lines" enable row level security;


  create table "unipds"."refunds" (
    "refund_id" uuid not null default gen_random_uuid(),
    "charge_id" uuid not null,
    "voomp_venda_id" text not null,
    "tipo" text not null,
    "valor" numeric(12,2) not null,
    "motivo" text,
    "ocorrido_em" timestamp with time zone,
    "created_at" timestamp with time zone not null default now()
      );


alter table "unipds"."refunds" enable row level security;


  create table "unipds"."students" (
    "student_id" uuid not null default gen_random_uuid(),
    "tenant_id" uuid not null,
    "cpf_cnpj" text not null,
    "nome" text not null,
    "email" text,
    "telefone" text,
    "endereco" jsonb,
    "uf_origem" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "unipds"."students" enable row level security;


  create table "unipds"."tenants" (
    "tenant_id" uuid not null default gen_random_uuid(),
    "nome" text not null,
    "cnpj" text not null,
    "ativo" boolean not null default true,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "unipds"."tenants" enable row level security;

alter sequence "financeiro"."lancamentos_id_seq" owned by "financeiro"."lancamentos"."id";

alter sequence "financeiro"."mapeamento_categorias_id_seq" owned by "financeiro"."mapeamento_categorias"."id";

alter sequence "financeiro"."sync_log_id_seq" owned by "financeiro"."sync_log"."id";

CREATE UNIQUE INDEX cobranca_casos_pkey ON cobranca.cobranca_casos USING btree (caso_id);

CREATE UNIQUE INDEX cobranca_interacoes_pkey ON cobranca.cobranca_interacoes USING btree (interacao_id);

CREATE UNIQUE INDEX cobranca_negociacoes_pkey ON cobranca.cobranca_negociacoes USING btree (negociacao_id);

CREATE INDEX idx_casos_faixa ON cobranca.cobranca_casos USING btree (faixa_aging);

CREATE INDEX idx_casos_status ON cobranca.cobranca_casos USING btree (status);

CREATE INDEX idx_casos_tenant ON cobranca.cobranca_casos USING btree (tenant_id);

CREATE INDEX idx_interacoes_caso ON cobranca.cobranca_interacoes USING btree (caso_id);

CREATE INDEX idx_negociacoes_caso ON cobranca.cobranca_negociacoes USING btree (caso_id);

CREATE UNIQUE INDEX uq_caso_por_contrato ON cobranca.cobranca_casos USING btree (contract_id);

CREATE INDEX idx_lancamentos_categoria ON financeiro.lancamentos USING btree (categoria);

CREATE INDEX idx_lancamentos_cod_integracao ON financeiro.lancamentos USING btree (cod_integracao) WHERE (cod_integracao IS NOT NULL);

CREATE INDEX idx_lancamentos_data ON financeiro.lancamentos USING btree (data);

CREATE INDEX idx_lancamentos_departamento ON financeiro.lancamentos USING btree (departamento);

CREATE INDEX idx_lancamentos_empresa_data ON financeiro.lancamentos USING btree (empresa, data);

CREATE INDEX idx_lancamentos_numero_doc ON financeiro.lancamentos USING btree (numero_documento) WHERE (numero_documento IS NOT NULL);

CREATE UNIQUE INDEX lancamentos_pkey ON financeiro.lancamentos USING btree (id);

CREATE UNIQUE INDEX mapeamento_categorias_pkey ON financeiro.mapeamento_categorias USING btree (empresa, codigo_omie);

CREATE UNIQUE INDEX sync_log_pkey ON financeiro.sync_log USING btree (id);

CREATE UNIQUE INDEX uq_lancamento ON financeiro.lancamentos USING btree (empresa, id_omie);

CREATE UNIQUE INDEX charges_pkey ON unipds.charges USING btree (charge_id);

CREATE UNIQUE INDEX charges_voomp_venda_id_key ON unipds.charges USING btree (voomp_venda_id);

CREATE UNIQUE INDEX conciliacao_links_contract_unique ON unipds.conciliacao_links USING btree (contract_id);

CREATE UNIQUE INDEX conciliacao_links_pipe_unique ON unipds.conciliacao_links USING btree (tenant_id, pipe_deal_id);

CREATE UNIQUE INDEX conciliacao_links_pkey ON unipds.conciliacao_links USING btree (link_id);

CREATE UNIQUE INDEX conciliacao_runs_pkey ON unipds.conciliacao_runs USING btree (run_id);

CREATE UNIQUE INDEX contracts_pkey ON unipds.contracts USING btree (contract_id);

CREATE UNIQUE INDEX contracts_tenant_id_contract_ref_key ON unipds.contracts USING btree (tenant_id, contract_ref);

CREATE UNIQUE INDEX contracts_tenant_id_voomp_contrato_id_key ON unipds.contracts USING btree (tenant_id, voomp_contrato_id);

CREATE UNIQUE INDEX fechamentos_mensais_pkey ON unipds.fechamentos_mensais USING btree (fechamento_id);

CREATE UNIQUE INDEX fechamentos_mensais_unique ON unipds.fechamentos_mensais USING btree (tenant_id, ano_mes);

CREATE UNIQUE INDEX fontes_pkey ON unipds.fontes USING btree (fonte_id);

CREATE INDEX idx_attempts_contract ON unipds.payment_attempts USING btree (contract_id);

CREATE INDEX idx_charges_atraso ON unipds.charges USING btree (dias_atraso) WHERE (dias_atraso > 0);

CREATE INDEX idx_charges_contract ON unipds.charges USING btree (contract_id);

CREATE INDEX idx_charges_status ON unipds.charges USING btree (status);

CREATE INDEX idx_charges_vencimento ON unipds.charges USING btree (data_vencimento) WHERE (status = 'Aguardando Pagamento'::text);

CREATE INDEX idx_contracts_data ON unipds.contracts USING btree (tenant_id, data_primeira_venda);

CREATE INDEX idx_contracts_product ON unipds.contracts USING btree (product_id);

CREATE INDEX idx_contracts_status ON unipds.contracts USING btree (tenant_id, status_contrato);

CREATE INDEX idx_contracts_student ON unipds.contracts USING btree (student_id);

CREATE INDEX idx_contracts_voomp_id ON unipds.contracts USING btree (voomp_contrato_id) WHERE (voomp_contrato_id IS NOT NULL);

CREATE INDEX idx_fechamentos_tenant_estado ON unipds.fechamentos_mensais USING btree (tenant_id, estado);

CREATE INDEX idx_ingestao_status_tenant_anomes ON unipds.ingestao_status USING btree (tenant_id, ano_mes, status);

CREATE INDEX idx_links_divergencia_classe ON unipds.conciliacao_links USING btree (tenant_id, ano_mes, divergencia_classe) WHERE (divergencia_classe = ANY (ARRAY['CUPOM_PROVAVEL'::text, 'MATERIAL'::text]));

CREATE INDEX idx_links_run ON unipds.conciliacao_links USING btree (run_id);

CREATE INDEX idx_links_tenant_anomes ON unipds.conciliacao_links USING btree (tenant_id, ano_mes);

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

CREATE INDEX idx_runs_tenant_anomes ON unipds.conciliacao_runs USING btree (tenant_id, ano_mes, iniciado_em DESC);

CREATE INDEX idx_students_tenant_cpf ON unipds.students USING btree (tenant_id, cpf_cnpj);

CREATE INDEX idx_students_tenant_email ON unipds.students USING btree (tenant_id, email);

CREATE UNIQUE INDEX ingestao_status_pkey ON unipds.ingestao_status USING btree (ingestao_status_id);

CREATE UNIQUE INDEX ingestao_status_unique ON unipds.ingestao_status USING btree (tenant_id, fonte_id, ano_mes);

CREATE UNIQUE INDEX payment_attempts_pkey ON unipds.payment_attempts USING btree (attempt_id);

CREATE UNIQUE INDEX payment_attempts_voomp_venda_id_key ON unipds.payment_attempts USING btree (voomp_venda_id);

CREATE UNIQUE INDEX pipe_deals_pkey ON unipds.pipe_deals USING btree (tenant_id, pipe_deal_id);

CREATE UNIQUE INDEX previsao_parcelas_pkey ON unipds.previsao_parcelas USING btree (previsao_id);

CREATE UNIQUE INDEX previsao_parcelas_previsao_ref_key ON unipds.previsao_parcelas USING btree (previsao_ref);

CREATE UNIQUE INDEX products_pkey ON unipds.products USING btree (product_id);

CREATE UNIQUE INDEX products_tenant_id_voomp_produto_id_key ON unipds.products USING btree (tenant_id, voomp_produto_id);

CREATE UNIQUE INDEX raw_imports_fonte_id_sha256_hash_key ON unipds.raw_imports USING btree (fonte_id, sha256_hash);

CREATE UNIQUE INDEX raw_imports_pkey ON unipds.raw_imports USING btree (import_id);

CREATE UNIQUE INDEX raw_lines_import_id_linha_numero_key ON unipds.raw_lines USING btree (import_id, linha_numero);

CREATE UNIQUE INDEX raw_lines_pkey ON unipds.raw_lines USING btree (line_id);

CREATE UNIQUE INDEX refunds_pkey ON unipds.refunds USING btree (refund_id);

CREATE UNIQUE INDEX refunds_voomp_venda_id_key ON unipds.refunds USING btree (voomp_venda_id);

CREATE UNIQUE INDEX students_pkey ON unipds.students USING btree (student_id);

CREATE UNIQUE INDEX students_tenant_id_cpf_cnpj_key ON unipds.students USING btree (tenant_id, cpf_cnpj);

CREATE UNIQUE INDEX tenants_cnpj_key ON unipds.tenants USING btree (cnpj);

CREATE UNIQUE INDEX tenants_pkey ON unipds.tenants USING btree (tenant_id);

alter table "cobranca"."cobranca_casos" add constraint "cobranca_casos_pkey" PRIMARY KEY using index "cobranca_casos_pkey";

alter table "cobranca"."cobranca_interacoes" add constraint "cobranca_interacoes_pkey" PRIMARY KEY using index "cobranca_interacoes_pkey";

alter table "cobranca"."cobranca_negociacoes" add constraint "cobranca_negociacoes_pkey" PRIMARY KEY using index "cobranca_negociacoes_pkey";

alter table "financeiro"."lancamentos" add constraint "lancamentos_pkey" PRIMARY KEY using index "lancamentos_pkey";

alter table "financeiro"."mapeamento_categorias" add constraint "mapeamento_categorias_pkey" PRIMARY KEY using index "mapeamento_categorias_pkey";

alter table "financeiro"."sync_log" add constraint "sync_log_pkey" PRIMARY KEY using index "sync_log_pkey";

alter table "unipds"."charges" add constraint "charges_pkey" PRIMARY KEY using index "charges_pkey";

alter table "unipds"."conciliacao_links" add constraint "conciliacao_links_pkey" PRIMARY KEY using index "conciliacao_links_pkey";

alter table "unipds"."conciliacao_runs" add constraint "conciliacao_runs_pkey" PRIMARY KEY using index "conciliacao_runs_pkey";

alter table "unipds"."contracts" add constraint "contracts_pkey" PRIMARY KEY using index "contracts_pkey";

alter table "unipds"."fechamentos_mensais" add constraint "fechamentos_mensais_pkey" PRIMARY KEY using index "fechamentos_mensais_pkey";

alter table "unipds"."fontes" add constraint "fontes_pkey" PRIMARY KEY using index "fontes_pkey";

alter table "unipds"."ingestao_status" add constraint "ingestao_status_pkey" PRIMARY KEY using index "ingestao_status_pkey";

alter table "unipds"."payment_attempts" add constraint "payment_attempts_pkey" PRIMARY KEY using index "payment_attempts_pkey";

alter table "unipds"."pipe_deals" add constraint "pipe_deals_pkey" PRIMARY KEY using index "pipe_deals_pkey";

alter table "unipds"."previsao_parcelas" add constraint "previsao_parcelas_pkey" PRIMARY KEY using index "previsao_parcelas_pkey";

alter table "unipds"."products" add constraint "products_pkey" PRIMARY KEY using index "products_pkey";

alter table "unipds"."raw_imports" add constraint "raw_imports_pkey" PRIMARY KEY using index "raw_imports_pkey";

alter table "unipds"."raw_lines" add constraint "raw_lines_pkey" PRIMARY KEY using index "raw_lines_pkey";

alter table "unipds"."refunds" add constraint "refunds_pkey" PRIMARY KEY using index "refunds_pkey";

alter table "unipds"."students" add constraint "students_pkey" PRIMARY KEY using index "students_pkey";

alter table "unipds"."tenants" add constraint "tenants_pkey" PRIMARY KEY using index "tenants_pkey";

alter table "cobranca"."cobranca_casos" add constraint "cobranca_casos_contract_id_fkey" FOREIGN KEY (contract_id) REFERENCES unipds.contracts(contract_id) not valid;

alter table "cobranca"."cobranca_casos" validate constraint "cobranca_casos_contract_id_fkey";

alter table "cobranca"."cobranca_casos" add constraint "uq_caso_por_contrato" UNIQUE using index "uq_caso_por_contrato";

alter table "cobranca"."cobranca_interacoes" add constraint "cobranca_interacoes_caso_id_fkey" FOREIGN KEY (caso_id) REFERENCES cobranca.cobranca_casos(caso_id) not valid;

alter table "cobranca"."cobranca_interacoes" validate constraint "cobranca_interacoes_caso_id_fkey";

alter table "cobranca"."cobranca_negociacoes" add constraint "cobranca_negociacoes_caso_id_fkey" FOREIGN KEY (caso_id) REFERENCES cobranca.cobranca_casos(caso_id) not valid;

alter table "cobranca"."cobranca_negociacoes" validate constraint "cobranca_negociacoes_caso_id_fkey";

alter table "financeiro"."lancamentos" add constraint "uq_lancamento" UNIQUE using index "uq_lancamento";

alter table "unipds"."charges" add constraint "charges_contract_id_fkey" FOREIGN KEY (contract_id) REFERENCES unipds.contracts(contract_id) not valid;

alter table "unipds"."charges" validate constraint "charges_contract_id_fkey";

alter table "unipds"."charges" add constraint "charges_metodo_pagamento_check" CHECK ((metodo_pagamento = ANY (ARRAY['Cartão de Crédito'::text, 'Boleto'::text, 'Pix'::text]))) not valid;

alter table "unipds"."charges" validate constraint "charges_metodo_pagamento_check";

alter table "unipds"."charges" add constraint "charges_status_check" CHECK ((status = ANY (ARRAY['Pago'::text, 'Aguardando Pagamento'::text, 'Reembolsado'::text, 'Chargeback'::text, 'Reembolso Pendente'::text]))) not valid;

alter table "unipds"."charges" validate constraint "charges_status_check";

alter table "unipds"."charges" add constraint "charges_voomp_venda_id_key" UNIQUE using index "charges_voomp_venda_id_key";

alter table "unipds"."conciliacao_links" add constraint "conciliacao_links_charge_fk" FOREIGN KEY (charge_id) REFERENCES unipds.charges(charge_id) not valid;

alter table "unipds"."conciliacao_links" validate constraint "conciliacao_links_charge_fk";

alter table "unipds"."conciliacao_links" add constraint "conciliacao_links_confianca_chk" CHECK (((confianca >= 0) AND (confianca <= 100))) not valid;

alter table "unipds"."conciliacao_links" validate constraint "conciliacao_links_confianca_chk";

alter table "unipds"."conciliacao_links" add constraint "conciliacao_links_contract_fk" FOREIGN KEY (contract_id) REFERENCES unipds.contracts(contract_id) ON DELETE CASCADE not valid;

alter table "unipds"."conciliacao_links" validate constraint "conciliacao_links_contract_fk";

alter table "unipds"."conciliacao_links" add constraint "conciliacao_links_contract_unique" UNIQUE using index "conciliacao_links_contract_unique";

alter table "unipds"."conciliacao_links" add constraint "conciliacao_links_criterio_chk" CHECK ((criterio = ANY (ARRAY['MANUAL'::text, 'CPF'::text, 'EMAIL'::text, 'NOME'::text, 'TELEFONE'::text, 'CROSS_TENANT'::text]))) not valid;

alter table "unipds"."conciliacao_links" validate constraint "conciliacao_links_criterio_chk";

alter table "unipds"."conciliacao_links" add constraint "conciliacao_links_divergencia_chk" CHECK (((divergencia_classe IS NULL) OR (divergencia_classe = ANY (ARRAY['IDENTICO'::text, 'CENTAVOS'::text, 'CUPOM_PROVAVEL'::text, 'MATERIAL'::text])))) not valid;

alter table "unipds"."conciliacao_links" validate constraint "conciliacao_links_divergencia_chk";

alter table "unipds"."conciliacao_links" add constraint "conciliacao_links_origem_chk" CHECK ((origem = ANY (ARRAY['AUTOMATICO'::text, 'MANUAL'::text]))) not valid;

alter table "unipds"."conciliacao_links" validate constraint "conciliacao_links_origem_chk";

alter table "unipds"."conciliacao_links" add constraint "conciliacao_links_pipe_fk" FOREIGN KEY (tenant_id, pipe_deal_id) REFERENCES unipds.pipe_deals(tenant_id, pipe_deal_id) ON DELETE CASCADE not valid;

alter table "unipds"."conciliacao_links" validate constraint "conciliacao_links_pipe_fk";

alter table "unipds"."conciliacao_links" add constraint "conciliacao_links_pipe_unique" UNIQUE using index "conciliacao_links_pipe_unique";

alter table "unipds"."conciliacao_links" add constraint "conciliacao_links_run_fk" FOREIGN KEY (run_id) REFERENCES unipds.conciliacao_runs(run_id) not valid;

alter table "unipds"."conciliacao_links" validate constraint "conciliacao_links_run_fk";

alter table "unipds"."conciliacao_links" add constraint "conciliacao_links_tenant_fk" FOREIGN KEY (tenant_id) REFERENCES unipds.tenants(tenant_id) not valid;

alter table "unipds"."conciliacao_links" validate constraint "conciliacao_links_tenant_fk";

alter table "unipds"."conciliacao_runs" add constraint "conciliacao_runs_fechamento_fk" FOREIGN KEY (fechamento_id) REFERENCES unipds.fechamentos_mensais(fechamento_id) not valid;

alter table "unipds"."conciliacao_runs" validate constraint "conciliacao_runs_fechamento_fk";

alter table "unipds"."conciliacao_runs" add constraint "conciliacao_runs_status_chk" CHECK ((status = ANY (ARRAY['EM_EXECUCAO'::text, 'CONCLUIDO'::text, 'ERRO'::text]))) not valid;

alter table "unipds"."conciliacao_runs" validate constraint "conciliacao_runs_status_chk";

alter table "unipds"."conciliacao_runs" add constraint "conciliacao_runs_tenant_fk" FOREIGN KEY (tenant_id) REFERENCES unipds.tenants(tenant_id) not valid;

alter table "unipds"."conciliacao_runs" validate constraint "conciliacao_runs_tenant_fk";

alter table "unipds"."contracts" add constraint "contracts_contrato_espelho_de_fkey" FOREIGN KEY (contrato_espelho_de) REFERENCES unipds.contracts(contract_id) not valid;

alter table "unipds"."contracts" validate constraint "contracts_contrato_espelho_de_fkey";

alter table "unipds"."contracts" add constraint "contracts_fonte_id_fkey" FOREIGN KEY (fonte_id) REFERENCES unipds.fontes(fonte_id) not valid;

alter table "unipds"."contracts" validate constraint "contracts_fonte_id_fkey";

alter table "unipds"."contracts" add constraint "contracts_product_id_fkey" FOREIGN KEY (product_id) REFERENCES unipds.products(product_id) not valid;

alter table "unipds"."contracts" validate constraint "contracts_product_id_fkey";

alter table "unipds"."contracts" add constraint "contracts_status_contrato_check" CHECK ((status_contrato = ANY (ARRAY['Pago'::text, 'Não pago'::text, 'Aguardando pagamento'::text, 'Atrasado'::text, 'Cancelado'::text, 'Encerrado'::text, 'Reembolsado'::text, 'Recusado'::text, 'failed'::text, 'Criado'::text]))) not valid;

alter table "unipds"."contracts" validate constraint "contracts_status_contrato_check";

alter table "unipds"."contracts" add constraint "contracts_student_id_fkey" FOREIGN KEY (student_id) REFERENCES unipds.students(student_id) not valid;

alter table "unipds"."contracts" validate constraint "contracts_student_id_fkey";

alter table "unipds"."contracts" add constraint "contracts_tenant_id_contract_ref_key" UNIQUE using index "contracts_tenant_id_contract_ref_key";

alter table "unipds"."contracts" add constraint "contracts_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES unipds.tenants(tenant_id) not valid;

alter table "unipds"."contracts" validate constraint "contracts_tenant_id_fkey";

alter table "unipds"."contracts" add constraint "contracts_tenant_id_voomp_contrato_id_key" UNIQUE using index "contracts_tenant_id_voomp_contrato_id_key";

alter table "unipds"."contracts" add constraint "contracts_tipo_cobranca_check" CHECK ((tipo_cobranca = ANY (ARRAY['Assinatura'::text, 'Único'::text]))) not valid;

alter table "unipds"."contracts" validate constraint "contracts_tipo_cobranca_check";

alter table "unipds"."fechamentos_mensais" add constraint "fechamentos_anomes_chk" CHECK ((ano_mes ~ '^\d{4}-(0[1-9]|1[0-2])$'::text)) not valid;

alter table "unipds"."fechamentos_mensais" validate constraint "fechamentos_anomes_chk";

alter table "unipds"."fechamentos_mensais" add constraint "fechamentos_estado_chk" CHECK ((estado = ANY (ARRAY['ABERTO'::text, 'EM_REVISAO'::text, 'FECHADO'::text, 'REABERTO'::text]))) not valid;

alter table "unipds"."fechamentos_mensais" validate constraint "fechamentos_estado_chk";

alter table "unipds"."fechamentos_mensais" add constraint "fechamentos_mensais_tenant_fk" FOREIGN KEY (tenant_id) REFERENCES unipds.tenants(tenant_id) not valid;

alter table "unipds"."fechamentos_mensais" validate constraint "fechamentos_mensais_tenant_fk";

alter table "unipds"."fechamentos_mensais" add constraint "fechamentos_mensais_unique" UNIQUE using index "fechamentos_mensais_unique";

alter table "unipds"."fontes" add constraint "fontes_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES unipds.tenants(tenant_id) not valid;

alter table "unipds"."fontes" validate constraint "fontes_tenant_id_fkey";

alter table "unipds"."ingestao_status" add constraint "ingestao_anomes_chk" CHECK ((ano_mes ~ '^\d{4}-(0[1-9]|1[0-2])$'::text)) not valid;

alter table "unipds"."ingestao_status" validate constraint "ingestao_anomes_chk";

alter table "unipds"."ingestao_status" add constraint "ingestao_status_chk" CHECK ((status = ANY (ARRAY['PARCIAL'::text, 'COMPLETA'::text]))) not valid;

alter table "unipds"."ingestao_status" validate constraint "ingestao_status_chk";

alter table "unipds"."ingestao_status" add constraint "ingestao_status_fonte_fk" FOREIGN KEY (fonte_id) REFERENCES unipds.fontes(fonte_id) not valid;

alter table "unipds"."ingestao_status" validate constraint "ingestao_status_fonte_fk";

alter table "unipds"."ingestao_status" add constraint "ingestao_status_import_fk" FOREIGN KEY (ultimo_import_id) REFERENCES unipds.raw_imports(import_id) not valid;

alter table "unipds"."ingestao_status" validate constraint "ingestao_status_import_fk";

alter table "unipds"."ingestao_status" add constraint "ingestao_status_tenant_fk" FOREIGN KEY (tenant_id) REFERENCES unipds.tenants(tenant_id) not valid;

alter table "unipds"."ingestao_status" validate constraint "ingestao_status_tenant_fk";

alter table "unipds"."ingestao_status" add constraint "ingestao_status_unique" UNIQUE using index "ingestao_status_unique";

alter table "unipds"."payment_attempts" add constraint "payment_attempts_contract_id_fkey" FOREIGN KEY (contract_id) REFERENCES unipds.contracts(contract_id) not valid;

alter table "unipds"."payment_attempts" validate constraint "payment_attempts_contract_id_fkey";

alter table "unipds"."payment_attempts" add constraint "payment_attempts_metodo_pagamento_check" CHECK ((metodo_pagamento = ANY (ARRAY['Cartão de Crédito'::text, 'Boleto'::text, 'Pix'::text]))) not valid;

alter table "unipds"."payment_attempts" validate constraint "payment_attempts_metodo_pagamento_check";

alter table "unipds"."payment_attempts" add constraint "payment_attempts_voomp_venda_id_key" UNIQUE using index "payment_attempts_voomp_venda_id_key";

alter table "unipds"."pipe_deals" add constraint "pipe_deals_status_chk" CHECK ((status = ANY (ARRAY['Ganho'::text, 'Perdido'::text, 'Em andamento'::text]))) not valid;

alter table "unipds"."pipe_deals" validate constraint "pipe_deals_status_chk";

alter table "unipds"."pipe_deals" add constraint "pipe_deals_tenant_fk" FOREIGN KEY (tenant_id) REFERENCES unipds.tenants(tenant_id) not valid;

alter table "unipds"."pipe_deals" validate constraint "pipe_deals_tenant_fk";

alter table "unipds"."previsao_parcelas" add constraint "previsao_parcelas_charge_id_fkey" FOREIGN KEY (charge_id) REFERENCES unipds.charges(charge_id) not valid;

alter table "unipds"."previsao_parcelas" validate constraint "previsao_parcelas_charge_id_fkey";

alter table "unipds"."previsao_parcelas" add constraint "previsao_parcelas_contract_id_fkey" FOREIGN KEY (contract_id) REFERENCES unipds.contracts(contract_id) not valid;

alter table "unipds"."previsao_parcelas" validate constraint "previsao_parcelas_contract_id_fkey";

alter table "unipds"."previsao_parcelas" add constraint "previsao_parcelas_previsao_ref_key" UNIQUE using index "previsao_parcelas_previsao_ref_key";

alter table "unipds"."previsao_parcelas" add constraint "previsao_parcelas_status_check" CHECK ((status = ANY (ARRAY['previsto'::text, 'pago'::text, 'vencido'::text, 'cancelado'::text]))) not valid;

alter table "unipds"."previsao_parcelas" validate constraint "previsao_parcelas_status_check";

alter table "unipds"."products" add constraint "products_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES unipds.tenants(tenant_id) not valid;

alter table "unipds"."products" validate constraint "products_tenant_id_fkey";

alter table "unipds"."products" add constraint "products_tenant_id_voomp_produto_id_key" UNIQUE using index "products_tenant_id_voomp_produto_id_key";

alter table "unipds"."raw_imports" add constraint "raw_imports_fonte_id_fkey" FOREIGN KEY (fonte_id) REFERENCES unipds.fontes(fonte_id) not valid;

alter table "unipds"."raw_imports" validate constraint "raw_imports_fonte_id_fkey";

alter table "unipds"."raw_imports" add constraint "raw_imports_fonte_id_sha256_hash_key" UNIQUE using index "raw_imports_fonte_id_sha256_hash_key";

alter table "unipds"."raw_imports" add constraint "raw_imports_status_check" CHECK ((status = ANY (ARRAY['pendente'::text, 'processando'::text, 'concluido'::text, 'erro'::text]))) not valid;

alter table "unipds"."raw_imports" validate constraint "raw_imports_status_check";

alter table "unipds"."raw_lines" add constraint "raw_lines_import_id_fkey" FOREIGN KEY (import_id) REFERENCES unipds.raw_imports(import_id) not valid;

alter table "unipds"."raw_lines" validate constraint "raw_lines_import_id_fkey";

alter table "unipds"."raw_lines" add constraint "raw_lines_import_id_linha_numero_key" UNIQUE using index "raw_lines_import_id_linha_numero_key";

alter table "unipds"."raw_lines" add constraint "raw_lines_status_check" CHECK ((status = ANY (ARRAY['pendente'::text, 'processado'::text, 'ignorado'::text, 'erro'::text]))) not valid;

alter table "unipds"."raw_lines" validate constraint "raw_lines_status_check";

alter table "unipds"."refunds" add constraint "refunds_charge_id_fkey" FOREIGN KEY (charge_id) REFERENCES unipds.charges(charge_id) not valid;

alter table "unipds"."refunds" validate constraint "refunds_charge_id_fkey";

alter table "unipds"."refunds" add constraint "refunds_motivo_check" CHECK ((motivo = ANY (ARRAY['Desistiu da compra'::text, 'Comprou errado'::text, 'Compra duplicada'::text, 'Outros'::text]))) not valid;

alter table "unipds"."refunds" validate constraint "refunds_motivo_check";

alter table "unipds"."refunds" add constraint "refunds_tipo_check" CHECK ((tipo = ANY (ARRAY['Reembolso'::text, 'Chargeback'::text]))) not valid;

alter table "unipds"."refunds" validate constraint "refunds_tipo_check";

alter table "unipds"."refunds" add constraint "refunds_voomp_venda_id_key" UNIQUE using index "refunds_voomp_venda_id_key";

alter table "unipds"."students" add constraint "students_tenant_id_cpf_cnpj_key" UNIQUE using index "students_tenant_id_cpf_cnpj_key";

alter table "unipds"."students" add constraint "students_tenant_id_fkey" FOREIGN KEY (tenant_id) REFERENCES unipds.tenants(tenant_id) not valid;

alter table "unipds"."students" validate constraint "students_tenant_id_fkey";

alter table "unipds"."tenants" add constraint "tenants_cnpj_key" UNIQUE using index "tenants_cnpj_key";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION cobranca.atualizar_ultima_interacao()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    UPDATE cobranca.cobranca_casos
    SET data_ultima_interacao = NOW()
    WHERE caso_id = NEW.caso_id;
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION cobranca.registrar_encerramento()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.status IN ('pago', 'baixado', 'extrajudicial')
       AND OLD.status NOT IN ('pago', 'baixado', 'extrajudicial') THEN
        NEW.data_encerramento = NOW();
    END IF;
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION cobranca.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function$
;

create or replace view "cobranca"."v_casos_completos" as  SELECT cc.caso_id,
    cc.contract_id,
    cc.tenant_id,
        CASE
            WHEN (cc.tenant_id = '70b668e4-be85-459b-8dbb-3876929ac850'::uuid) THEN 'Java'::text
            WHEN (cc.tenant_id = 'e717e24d-fb30-4ed0-83d3-bb8ea0b66783'::uuid) THEN 'IA'::text
            ELSE NULL::text
        END AS tenant_nome,
    cc.status,
    cc.faixa_aging,
    cc.valor_total_aberto,
    cc.parcelas_vencidas,
    cc.valor_revertido,
    cc.data_pagamento_revertido,
    cc.responsavel,
    cc.data_abertura,
    cc.data_ultima_interacao,
    cc.data_encerramento,
    cc.observacao_encerramento,
    c.contract_ref,
    c.voomp_contrato_id,
    c.status_contrato,
    c.tipo_cobranca,
    s.nome,
    s.cpf_cnpj,
    s.email,
    s.telefone,
    ( SELECT count(*) AS count
           FROM cobranca.cobranca_interacoes ci
          WHERE (ci.caso_id = cc.caso_id)) AS total_contatos,
    ( SELECT count(*) AS count
           FROM cobranca.cobranca_interacoes ci
          WHERE ((ci.caso_id = cc.caso_id) AND (ci.houve_retorno = true))) AS total_retornos,
    ( SELECT max(ci.data_contato) AS max
           FROM cobranca.cobranca_interacoes ci
          WHERE (ci.caso_id = cc.caso_id)) AS data_ultimo_contato,
    ( SELECT cn.status
           FROM cobranca.cobranca_negociacoes cn
          WHERE (cn.caso_id = cc.caso_id)
          ORDER BY cn.created_at DESC
         LIMIT 1) AS status_negociacao,
    ( SELECT cn.valor_total_acordado
           FROM cobranca.cobranca_negociacoes cn
          WHERE (cn.caso_id = cc.caso_id)
          ORDER BY cn.created_at DESC
         LIMIT 1) AS valor_negociado,
    ( SELECT cn.data_primeiro_vencimento
           FROM cobranca.cobranca_negociacoes cn
          WHERE (cn.caso_id = cc.caso_id)
          ORDER BY cn.created_at DESC
         LIMIT 1) AS proximo_vencimento_acordo
   FROM ((cobranca.cobranca_casos cc
     JOIN unipds.contracts c ON ((c.contract_id = cc.contract_id)))
     JOIN unipds.students s ON ((s.student_id = c.student_id)))
  ORDER BY cc.faixa_aging DESC, cc.valor_total_aberto DESC;


create or replace view "cobranca"."v_kpis" as  SELECT count(*) AS total_casos,
    count(*) FILTER (WHERE (status = 'em_aberto'::cobranca.status_caso)) AS casos_em_aberto,
    count(*) FILTER (WHERE (status = 'em_contato'::cobranca.status_caso)) AS casos_em_contato,
    count(*) FILTER (WHERE ((status = 'em_negociacao'::cobranca.status_caso) OR (status = 'acordo_ativo'::cobranca.status_caso))) AS casos_em_negociacao,
    count(*) FILTER (WHERE (status = 'pago'::cobranca.status_caso)) AS casos_revertidos,
    count(*) FILTER (WHERE (status = 'extrajudicial'::cobranca.status_caso)) AS casos_extrajudicial,
    count(*) FILTER (WHERE (status = 'baixado'::cobranca.status_caso)) AS casos_baixados,
    round(sum(valor_total_aberto), 2) AS volume_carteira,
    round(sum(valor_revertido) FILTER (WHERE (status = 'pago'::cobranca.status_caso)), 2) AS volume_revertido,
    round(((sum(valor_revertido) FILTER (WHERE (status = 'pago'::cobranca.status_caso)) / NULLIF(sum(valor_total_aberto), (0)::numeric)) * (100)::numeric), 1) AS taxa_recuperacao_pct,
    ( SELECT count(*) AS count
           FROM cobranca.cobranca_interacoes) AS total_contatos,
    ( SELECT count(*) AS count
           FROM cobranca.cobranca_interacoes
          WHERE (cobranca_interacoes.houve_retorno = true)) AS total_retornos,
    ( SELECT round((((count(*) FILTER (WHERE (cobranca_interacoes.houve_retorno = true)))::numeric / (NULLIF(count(*), 0))::numeric) * (100)::numeric), 1) AS round
           FROM cobranca.cobranca_interacoes) AS taxa_retorno_pct,
    ( SELECT count(*) AS count
           FROM cobranca.cobranca_negociacoes
          WHERE (cobranca_negociacoes.status = 'em_andamento'::cobranca.status_acordo)) AS acordos_ativos,
    ( SELECT round(sum(cobranca_negociacoes.valor_total_acordado), 2) AS round
           FROM cobranca.cobranca_negociacoes
          WHERE (cobranca_negociacoes.status = 'em_andamento'::cobranca.status_acordo)) AS volume_em_acordo,
    ( SELECT round(sum(cobranca_negociacoes.valor_total_acordado), 2) AS round
           FROM cobranca.cobranca_negociacoes
          WHERE (cobranca_negociacoes.status = 'cumprido'::cobranca.status_acordo)) AS volume_acordos_cumpridos
   FROM cobranca.cobranca_casos;


create or replace view "financeiro"."ciclo_financeiro_mensal" as  WITH entradas AS (
         SELECT lancamentos.empresa,
            date_trunc('month'::text, (lancamentos.data)::timestamp with time zone) AS mes,
            avg((lancamentos.data - (date_trunc('month'::text, (lancamentos.data)::timestamp with time zone))::date)) AS pmr_dias,
            count(*) AS qtd_recebimentos,
            sum(lancamentos.valor) AS total_recebido
           FROM financeiro.lancamentos
          WHERE ((lancamentos.valor > (0)::numeric) AND (lancamentos.conta_corrente ~~* '%voomp%'::text) AND (lancamentos.data IS NOT NULL))
          GROUP BY lancamentos.empresa, (date_trunc('month'::text, (lancamentos.data)::timestamp with time zone))
        ), saidas AS (
         SELECT lancamentos.empresa,
            date_trunc('month'::text, (lancamentos.data)::timestamp with time zone) AS mes,
            avg((lancamentos.data - (date_trunc('month'::text, (lancamentos.data)::timestamp with time zone))::date)) AS pmp_dias,
            count(*) AS qtd_pagamentos,
            sum(abs(lancamentos.valor)) AS total_pago
           FROM financeiro.lancamentos
          WHERE ((lancamentos.valor < (0)::numeric) AND (lancamentos.conta_corrente !~~* '%voomp%'::text) AND (lancamentos.data IS NOT NULL))
          GROUP BY lancamentos.empresa, (date_trunc('month'::text, (lancamentos.data)::timestamp with time zone))
        ), saldo AS (
         SELECT lancamentos.empresa,
            date_trunc('month'::text, (lancamentos.data)::timestamp with time zone) AS mes,
            sum(lancamentos.valor) AS saldo_liquido
           FROM financeiro.lancamentos
          WHERE (lancamentos.data IS NOT NULL)
          GROUP BY lancamentos.empresa, (date_trunc('month'::text, (lancamentos.data)::timestamp with time zone))
        )
 SELECT COALESCE(e.empresa, s2.empresa) AS empresa,
    COALESCE(e.mes, s2.mes) AS mes,
    round(e.pmr_dias, 1) AS pmr_dias,
    round(s2.pmp_dias, 1) AS pmp_dias,
    round((e.pmr_dias - s2.pmp_dias), 1) AS ciclo_caixa_dias,
    round(e.total_recebido, 2) AS total_recebido,
    round(s2.total_pago, 2) AS total_pago,
    round(sl.saldo_liquido, 2) AS saldo_liquido_mes,
    e.qtd_recebimentos,
    s2.qtd_pagamentos
   FROM ((entradas e
     FULL JOIN saidas s2 ON (((e.empresa = s2.empresa) AND (e.mes = s2.mes))))
     LEFT JOIN saldo sl ON (((COALESCE(e.empresa, s2.empresa) = sl.empresa) AND (COALESCE(e.mes, s2.mes) = sl.mes))))
  ORDER BY COALESCE(e.empresa, s2.empresa), COALESCE(e.mes, s2.mes);


CREATE OR REPLACE FUNCTION financeiro.trigger_set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$function$
;

create or replace view "financeiro"."v_auditoria_voomp" as  WITH receita AS (
         SELECT lancamentos.numero_documento,
            sum(lancamentos.valor) AS omie_receita,
            count(*) AS omie_qtd_receita
           FROM financeiro.lancamentos
          WHERE ((lancamentos.valor > (0)::numeric) AND (lancamentos.numero_documento IS NOT NULL) AND (lancamentos.numero_documento <> ''::text))
          GROUP BY lancamentos.numero_documento
        ), taxa_gateway AS (
         SELECT lancamentos.numero_documento,
            sum(abs(lancamentos.valor)) AS omie_taxa,
            count(*) AS omie_qtd_taxa
           FROM financeiro.lancamentos
          WHERE ((lancamentos.valor < (0)::numeric) AND (lancamentos.categoria_omie = '2.01.02'::text) AND (lancamentos.numero_documento IS NOT NULL) AND (lancamentos.numero_documento <> ''::text))
          GROUP BY lancamentos.numero_documento
        ), comissao AS (
         SELECT lancamentos.numero_documento,
            sum(abs(lancamentos.valor)) AS omie_comissao,
            count(*) AS omie_qtd_comissao
           FROM financeiro.lancamentos
          WHERE ((lancamentos.valor < (0)::numeric) AND (lancamentos.categoria_omie = ANY (ARRAY['2.04.04'::text, '2.02.04'::text])) AND (lancamentos.numero_documento IS NOT NULL) AND (lancamentos.numero_documento <> ''::text))
          GROUP BY lancamentos.numero_documento
        ), devolucao AS (
         SELECT lancamentos.numero_documento,
            sum(abs(lancamentos.valor)) AS omie_devolucao,
            count(*) AS omie_qtd_devolucao
           FROM financeiro.lancamentos
          WHERE ((lancamentos.valor < (0)::numeric) AND (lancamentos.categoria_omie = '2.01.01'::text) AND (lancamentos.numero_documento IS NOT NULL) AND (lancamentos.numero_documento <> ''::text))
          GROUP BY lancamentos.numero_documento
        )
 SELECT ch.voomp_venda_id,
    ch.numero_parcela,
    st.nome AS aluno_nome,
    st.cpf_cnpj AS aluno_cpf,
    ct.nome_oferta,
    ct.tenant_id,
    l_emp.empresa AS omie_empresa,
    ch.data_pagamento AS voomp_data_pagamento,
    ch.data_liberacao_saldo AS voomp_data_liberacao,
    ch.valor_cobrado AS voomp_bruto,
    ch.taxa_voomp AS voomp_taxa,
    ch.comissao_coprodutor AS voomp_comissao,
    ch.valor_recebido AS voomp_liquido,
    ch.metodo_pagamento,
    COALESCE(r.omie_receita, (0)::numeric) AS omie_receita,
    COALESCE(tg.omie_taxa, (0)::numeric) AS omie_taxa,
    COALESCE(cm.omie_comissao, (0)::numeric) AS omie_comissao,
    COALESCE(dv.omie_devolucao, (0)::numeric) AS omie_devolucao,
    COALESCE(r.omie_qtd_receita, (0)::bigint) AS omie_qtd_receita,
    COALESCE(tg.omie_qtd_taxa, (0)::bigint) AS omie_qtd_taxa,
    COALESCE(cm.omie_qtd_comissao, (0)::bigint) AS omie_qtd_comissao,
    round((COALESCE(r.omie_receita, (0)::numeric) - ch.valor_cobrado), 2) AS div_receita,
    round((COALESCE(tg.omie_taxa, (0)::numeric) - ch.taxa_voomp), 2) AS div_taxa,
    round((COALESCE(cm.omie_comissao, (0)::numeric) - ch.comissao_coprodutor), 2) AS div_comissao,
    round(((((COALESCE(r.omie_receita, (0)::numeric) - COALESCE(tg.omie_taxa, (0)::numeric)) - COALESCE(cm.omie_comissao, (0)::numeric)) - COALESCE(dv.omie_devolucao, (0)::numeric)) - ch.valor_recebido), 2) AS div_liquido,
        CASE
            WHEN (r.omie_receita IS NULL) THEN 'SEM_LANCAMENTO'::text
            WHEN (dv.omie_devolucao > (0)::numeric) THEN 'DEVOLUCAO'::text
            WHEN (abs((COALESCE(r.omie_receita, (0)::numeric) - ch.valor_cobrado)) > 0.10) THEN 'DIV_RECEITA'::text
            WHEN (abs((COALESCE(tg.omie_taxa, (0)::numeric) - ch.taxa_voomp)) > 0.10) THEN 'DIV_TAXA'::text
            WHEN (abs((COALESCE(cm.omie_comissao, (0)::numeric) - ch.comissao_coprodutor)) > 0.10) THEN 'DIV_COMISSAO'::text
            ELSE 'OK'::text
        END AS status_auditoria
   FROM (((((((unipds.charges ch
     JOIN unipds.contracts ct ON ((ct.contract_id = ch.contract_id)))
     JOIN unipds.students st ON ((st.student_id = ct.student_id)))
     LEFT JOIN receita r ON ((r.numero_documento = ch.voomp_venda_id)))
     LEFT JOIN taxa_gateway tg ON ((tg.numero_documento = ch.voomp_venda_id)))
     LEFT JOIN comissao cm ON ((cm.numero_documento = ch.voomp_venda_id)))
     LEFT JOIN devolucao dv ON ((dv.numero_documento = ch.voomp_venda_id)))
     LEFT JOIN LATERAL ( SELECT lancamentos.empresa
           FROM financeiro.lancamentos
          WHERE ((lancamentos.numero_documento = ch.voomp_venda_id) AND (lancamentos.valor > (0)::numeric))
         LIMIT 1) l_emp ON (true))
  WHERE (ch.status = 'Pago'::text);


create or replace view "financeiro"."v_cruzamento_omie_voomp" as  SELECT ch.voomp_venda_id,
    ch.numero_parcela,
    ct.tenant_id,
    ct.contract_ref,
    st.nome AS aluno_nome,
    st.cpf_cnpj AS aluno_cpf,
    st.email AS aluno_email,
    ct.nome_oferta,
    ct.tipo_cobranca,
    ct.recorrencia_total,
    ch.valor_cobrado AS voomp_valor_cobrado,
    ch.taxa_voomp AS voomp_taxa,
    ch.comissao_coprodutor AS voomp_comissao,
    ch.valor_recebido AS voomp_valor_liquido,
    ch.status AS voomp_status,
    ch.data_vencimento AS voomp_data_vencimento,
    ch.data_pagamento AS voomp_data_pagamento,
    ch.metodo_pagamento AS voomp_metodo_pagamento,
    l.id_omie AS omie_id,
    l.valor AS omie_valor,
    l.data AS omie_data_lancamento,
    l.categoria AS omie_categoria,
    l.conta_corrente AS omie_conta_corrente,
    l.empresa AS omie_empresa,
        CASE
            WHEN (l.id_omie IS NULL) THEN 'SEM_OMIE'::text
            ELSE 'CASADO'::text
        END AS status_cruzamento,
    round(((l.valor)::numeric - (ch.valor_cobrado)::numeric), 2) AS divergencia_valor,
        CASE
            WHEN (l.id_omie IS NULL) THEN true
            WHEN (abs(((l.valor)::numeric - (ch.valor_cobrado)::numeric)) > 0.10) THEN true
            ELSE false
        END AS tem_divergencia
   FROM (((unipds.charges ch
     JOIN unipds.contracts ct ON ((ct.contract_id = ch.contract_id)))
     JOIN unipds.students st ON ((st.student_id = ct.student_id)))
     LEFT JOIN financeiro.lancamentos l ON (((l.numero_documento = ch.voomp_venda_id) AND (l.valor > (0)::numeric))))
  WHERE (ch.status = 'Pago'::text);


CREATE OR REPLACE FUNCTION public.get_cohort_assinaturas(p_tenant_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(mes_entrada text, mes_recebido text, mes_offset integer, contratos bigint, receita numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'unipds', 'public'
AS $function$
  WITH primeira_parcela AS (
    SELECT
      ch.contract_id,
      TO_CHAR(MIN(ch.data_pagamento), 'YYYY-MM') AS mes_entrada
    FROM unipds.charges ch
    JOIN unipds.contracts co ON ch.contract_id = co.contract_id
    WHERE ch.numero_parcela    = 1
      AND ch.status            = 'Pago'
      AND co.contrato_canonico  = true
      AND co.tipo_cobranca      = 'Assinatura'
      AND (p_tenant_id IS NULL OR co.tenant_id = p_tenant_id)
    GROUP BY ch.contract_id
  )
  SELECT
    pp.mes_entrada,
    TO_CHAR(ch.data_pagamento, 'YYYY-MM')                                          AS mes_recebido,
    (
      (DATE_PART('year',  ch.data_pagamento) - DATE_PART('year',  (pp.mes_entrada || '-01')::date)) * 12
      + DATE_PART('month', ch.data_pagamento) - DATE_PART('month', (pp.mes_entrada || '-01')::date)
    )::integer                                                                      AS mes_offset,
    COUNT(DISTINCT ch.contract_id)                                                  AS contratos,
    ROUND(SUM(ch.valor_recebido)::numeric, 2)                                       AS receita
  FROM unipds.charges ch
  JOIN unipds.contracts co ON ch.contract_id = co.contract_id
  JOIN primeira_parcela pp   ON ch.contract_id = pp.contract_id
  WHERE ch.status            = 'Pago'
    AND ch.data_pagamento    IS NOT NULL
    AND co.contrato_canonico  = true
    AND co.tipo_cobranca      = 'Assinatura'
    AND (p_tenant_id IS NULL OR co.tenant_id = p_tenant_id)
  GROUP BY pp.mes_entrada, TO_CHAR(ch.data_pagamento, 'YYYY-MM'), mes_offset
  ORDER BY pp.mes_entrada, mes_offset;
$function$
;

CREATE OR REPLACE FUNCTION public.get_curva_assinaturas(p_tenant_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(mes text, novas bigint, novas_ativas bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'unipds', 'public'
AS $function$
  SELECT
    TO_CHAR(data_primeira_venda, 'YYYY-MM')                        AS mes,
    COUNT(*)                                                        AS novas,
    COUNT(*) FILTER (WHERE status_contrato = 'Pago')               AS novas_ativas
  FROM unipds.contracts
  WHERE tipo_cobranca      = 'Assinatura'
    AND contrato_canonico   = true
    AND data_primeira_venda IS NOT NULL
    AND status_contrato NOT IN ('Reembolsado', 'Recusado')
    AND (p_tenant_id IS NULL OR tenant_id = p_tenant_id)
  GROUP BY TO_CHAR(data_primeira_venda, 'YYYY-MM')
  ORDER BY mes;
$function$
;

CREATE OR REPLACE FUNCTION public.get_faturamento_mensal(p_tenant_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(mes text, tipo_cobranca text, receita numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'unipds', 'public'
AS $function$
  SELECT
    TO_CHAR(ch.data_pagamento, 'YYYY-MM')      AS mes,
    co.tipo_cobranca,
    ROUND(SUM(ch.valor_recebido)::numeric, 2)  AS receita
  FROM unipds.charges ch
  JOIN unipds.contracts co ON ch.contract_id = co.contract_id
  WHERE ch.status             = 'Pago'
    AND ch.data_pagamento      IS NOT NULL
    AND co.contrato_canonico   = true
    AND (p_tenant_id IS NULL OR co.tenant_id = p_tenant_id)
  GROUP BY TO_CHAR(ch.data_pagamento, 'YYYY-MM'), co.tipo_cobranca
  ORDER BY mes, co.tipo_cobranca;
$function$
;

CREATE OR REPLACE FUNCTION public.get_parcelas_vencidas(p_contract_id uuid)
 RETURNS TABLE(previsao_id uuid, previsao_ref text, numero_parcela integer, total_parcelas integer, valor_previsto numeric, data_prevista date, status text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'unipds'
AS $function$
    SELECT previsao_id, previsao_ref, numero_parcela, total_parcelas,
           valor_previsto, data_prevista, status
    FROM unipds.previsao_parcelas
    WHERE contract_id = p_contract_id
      AND status = 'vencido'
    ORDER BY data_prevista ASC;
$function$
;

CREATE OR REPLACE FUNCTION unipds.atualizar_dias_atraso()
 RETURNS void
 LANGUAGE sql
AS $function$
    UPDATE unipds.charges
    SET dias_atraso = CASE
        WHEN status = 'Aguardando Pagamento' AND data_vencimento < CURRENT_DATE
        THEN (CURRENT_DATE - data_vencimento)
        ELSE 0
    END
    WHERE status = 'Aguardando Pagamento';
$function$
;

CREATE OR REPLACE FUNCTION unipds.executar_cruzamento(p_tenant_id uuid, p_ano_mes text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_run_id uuid; v_total_pipe int; v_total_voomp int;
  v_m_cpf int := 0; v_m_email int := 0; v_m_nome int := 0; v_m_tel int := 0; v_m_manual int := 0;
BEGIN
  INSERT INTO unipds.conciliacao_runs (tenant_id, ano_mes, status, parametros)
  VALUES (p_tenant_id, p_ano_mes, 'EM_EXECUCAO',
    jsonb_build_object('cascata', ARRAY['MANUAL','CPF','EMAIL','NOME','TELEFONE'],
                        'tolerancia_centavos', 1.00,
                        'valor_voomp', 'valor_recebido_total (lcv liquido)'))
  RETURNING run_id INTO v_run_id;

  SELECT COUNT(*) INTO v_total_pipe FROM unipds.pipe_deals
  WHERE tenant_id = p_tenant_id AND ano_mes = p_ano_mes AND status = 'Ganho';
  SELECT COUNT(*) INTO v_total_voomp FROM unipds.v_novos_alunos_voomp
  WHERE tenant_id = p_tenant_id AND ano_mes = p_ano_mes;
  SELECT COUNT(*) INTO v_m_manual FROM unipds.conciliacao_links
  WHERE tenant_id = p_tenant_id AND ano_mes = p_ano_mes AND criterio = 'MANUAL';

  -- CPF
  WITH candidatos AS (
    SELECT DISTINCT ON (pd.pipe_deal_id)
      pd.pipe_deal_id, pd.tenant_id, pd.ano_mes, pd.valor AS valor_pipe,
      v.contract_id, v.charge_id, v.valor_recebido_total, v.data_pagamento
    FROM unipds.pipe_deals pd
    JOIN unipds.v_novos_alunos_voomp v
      ON v.tenant_id = pd.tenant_id AND v.cpf_clean = pd.cpf_clean AND v.cpf_clean IS NOT NULL
    LEFT JOIN unipds.conciliacao_links cl_p ON cl_p.tenant_id = pd.tenant_id AND cl_p.pipe_deal_id = pd.pipe_deal_id
    LEFT JOIN unipds.conciliacao_links cl_c ON cl_c.contract_id = v.contract_id
    WHERE pd.tenant_id = p_tenant_id AND pd.ano_mes = p_ano_mes AND pd.status = 'Ganho'
      AND cl_p.link_id IS NULL AND cl_c.link_id IS NULL
    ORDER BY pd.pipe_deal_id, ABS(pd.valor - v.valor_recebido_total)
  )
  INSERT INTO unipds.conciliacao_links (
    tenant_id, ano_mes, pipe_deal_id, contract_id, charge_id, criterio, confianca,
    valor_pipe, valor_voomp, data_pagamento, divergencia_valor, divergencia_classe, origem, run_id)
  SELECT c.tenant_id, c.ano_mes, c.pipe_deal_id, c.contract_id, c.charge_id, 'CPF', 95,
    c.valor_pipe, c.valor_recebido_total, c.data_pagamento,
    ROUND((c.valor_pipe - c.valor_recebido_total)::numeric, 2),
    CASE
      WHEN c.valor_pipe = c.valor_recebido_total THEN 'IDENTICO'
      WHEN ABS(c.valor_pipe - c.valor_recebido_total) < 1 THEN 'CENTAVOS'
      WHEN ABS(c.valor_pipe - c.valor_recebido_total) / NULLIF(c.valor_pipe,0) BETWEEN 0.05 AND 0.20 THEN 'CUPOM_PROVAVEL'
      ELSE 'MATERIAL'
    END, 'AUTOMATICO', v_run_id
  FROM candidatos c ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_m_cpf = ROW_COUNT;

  -- EMAIL
  WITH candidatos AS (
    SELECT DISTINCT ON (pd.pipe_deal_id)
      pd.pipe_deal_id, pd.tenant_id, pd.ano_mes, pd.valor AS valor_pipe,
      v.contract_id, v.charge_id, v.valor_recebido_total, v.data_pagamento
    FROM unipds.pipe_deals pd
    JOIN unipds.v_novos_alunos_voomp v
      ON v.tenant_id = pd.tenant_id AND v.email_clean = pd.email_clean AND v.email_clean IS NOT NULL
    LEFT JOIN unipds.conciliacao_links cl_p ON cl_p.tenant_id = pd.tenant_id AND cl_p.pipe_deal_id = pd.pipe_deal_id
    LEFT JOIN unipds.conciliacao_links cl_c ON cl_c.contract_id = v.contract_id
    WHERE pd.tenant_id = p_tenant_id AND pd.ano_mes = p_ano_mes AND pd.status = 'Ganho'
      AND cl_p.link_id IS NULL AND cl_c.link_id IS NULL
    ORDER BY pd.pipe_deal_id, ABS(pd.valor - v.valor_recebido_total)
  )
  INSERT INTO unipds.conciliacao_links (
    tenant_id, ano_mes, pipe_deal_id, contract_id, charge_id, criterio, confianca,
    valor_pipe, valor_voomp, data_pagamento, divergencia_valor, divergencia_classe, origem, run_id)
  SELECT c.tenant_id, c.ano_mes, c.pipe_deal_id, c.contract_id, c.charge_id, 'EMAIL', 80,
    c.valor_pipe, c.valor_recebido_total, c.data_pagamento,
    ROUND((c.valor_pipe - c.valor_recebido_total)::numeric, 2),
    CASE
      WHEN c.valor_pipe = c.valor_recebido_total THEN 'IDENTICO'
      WHEN ABS(c.valor_pipe - c.valor_recebido_total) < 1 THEN 'CENTAVOS'
      WHEN ABS(c.valor_pipe - c.valor_recebido_total) / NULLIF(c.valor_pipe,0) BETWEEN 0.05 AND 0.20 THEN 'CUPOM_PROVAVEL'
      ELSE 'MATERIAL'
    END, 'AUTOMATICO', v_run_id
  FROM candidatos c ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_m_email = ROW_COUNT;

  -- NOME
  WITH candidatos AS (
    SELECT DISTINCT ON (pd.pipe_deal_id)
      pd.pipe_deal_id, pd.tenant_id, pd.ano_mes, pd.valor AS valor_pipe,
      v.contract_id, v.charge_id, v.valor_recebido_total, v.data_pagamento
    FROM unipds.pipe_deals pd
    JOIN unipds.v_novos_alunos_voomp v
      ON v.tenant_id = pd.tenant_id AND v.aluno_nome_norm = pd.pessoa_nome_norm AND v.aluno_nome_norm IS NOT NULL
    LEFT JOIN unipds.conciliacao_links cl_p ON cl_p.tenant_id = pd.tenant_id AND cl_p.pipe_deal_id = pd.pipe_deal_id
    LEFT JOIN unipds.conciliacao_links cl_c ON cl_c.contract_id = v.contract_id
    WHERE pd.tenant_id = p_tenant_id AND pd.ano_mes = p_ano_mes AND pd.status = 'Ganho'
      AND cl_p.link_id IS NULL AND cl_c.link_id IS NULL
    ORDER BY pd.pipe_deal_id, ABS(pd.valor - v.valor_recebido_total)
  )
  INSERT INTO unipds.conciliacao_links (
    tenant_id, ano_mes, pipe_deal_id, contract_id, charge_id, criterio, confianca,
    valor_pipe, valor_voomp, data_pagamento, divergencia_valor, divergencia_classe, origem, run_id)
  SELECT c.tenant_id, c.ano_mes, c.pipe_deal_id, c.contract_id, c.charge_id, 'NOME', 60,
    c.valor_pipe, c.valor_recebido_total, c.data_pagamento,
    ROUND((c.valor_pipe - c.valor_recebido_total)::numeric, 2),
    CASE
      WHEN c.valor_pipe = c.valor_recebido_total THEN 'IDENTICO'
      WHEN ABS(c.valor_pipe - c.valor_recebido_total) < 1 THEN 'CENTAVOS'
      WHEN ABS(c.valor_pipe - c.valor_recebido_total) / NULLIF(c.valor_pipe,0) BETWEEN 0.05 AND 0.20 THEN 'CUPOM_PROVAVEL'
      ELSE 'MATERIAL'
    END, 'AUTOMATICO', v_run_id
  FROM candidatos c ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_m_nome = ROW_COUNT;

  -- TELEFONE
  WITH candidatos AS (
    SELECT DISTINCT ON (pd.pipe_deal_id)
      pd.pipe_deal_id, pd.tenant_id, pd.ano_mes, pd.valor AS valor_pipe,
      v.contract_id, v.charge_id, v.valor_recebido_total, v.data_pagamento
    FROM unipds.pipe_deals pd
    JOIN unipds.v_novos_alunos_voomp v
      ON v.tenant_id = pd.tenant_id AND v.telefone_clean = pd.telefone_clean
      AND v.telefone_clean IS NOT NULL AND length(v.telefone_clean) >= 10
    LEFT JOIN unipds.conciliacao_links cl_p ON cl_p.tenant_id = pd.tenant_id AND cl_p.pipe_deal_id = pd.pipe_deal_id
    LEFT JOIN unipds.conciliacao_links cl_c ON cl_c.contract_id = v.contract_id
    WHERE pd.tenant_id = p_tenant_id AND pd.ano_mes = p_ano_mes AND pd.status = 'Ganho'
      AND cl_p.link_id IS NULL AND cl_c.link_id IS NULL
    ORDER BY pd.pipe_deal_id, ABS(pd.valor - v.valor_recebido_total)
  )
  INSERT INTO unipds.conciliacao_links (
    tenant_id, ano_mes, pipe_deal_id, contract_id, charge_id, criterio, confianca,
    valor_pipe, valor_voomp, data_pagamento, divergencia_valor, divergencia_classe, origem, run_id)
  SELECT c.tenant_id, c.ano_mes, c.pipe_deal_id, c.contract_id, c.charge_id, 'TELEFONE', 40,
    c.valor_pipe, c.valor_recebido_total, c.data_pagamento,
    ROUND((c.valor_pipe - c.valor_recebido_total)::numeric, 2),
    CASE
      WHEN c.valor_pipe = c.valor_recebido_total THEN 'IDENTICO'
      WHEN ABS(c.valor_pipe - c.valor_recebido_total) < 1 THEN 'CENTAVOS'
      WHEN ABS(c.valor_pipe - c.valor_recebido_total) / NULLIF(c.valor_pipe,0) BETWEEN 0.05 AND 0.20 THEN 'CUPOM_PROVAVEL'
      ELSE 'MATERIAL'
    END, 'AUTOMATICO', v_run_id
  FROM candidatos c ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_m_tel = ROW_COUNT;

  UPDATE unipds.conciliacao_runs SET
    status = 'CONCLUIDO', finalizado_em = now(),
    total_pipe_avaliados = v_total_pipe, total_voomp_avaliados = v_total_voomp,
    matches_cpf = v_m_cpf, matches_email = v_m_email,
    matches_nome = v_m_nome, matches_telefone = v_m_tel, matches_manual = v_m_manual,
    orfaos_pipe = v_total_pipe - (v_m_cpf + v_m_email + v_m_nome + v_m_tel + v_m_manual),
    orfaos_voomp = v_total_voomp - (v_m_cpf + v_m_email + v_m_nome + v_m_tel + v_m_manual)
  WHERE run_id = v_run_id;

  RETURN v_run_id;
EXCEPTION WHEN OTHERS THEN
  UPDATE unipds.conciliacao_runs SET
    status = 'ERRO', finalizado_em = now(), erro_msg = SQLERRM
  WHERE run_id = v_run_id;
  RAISE;
END;
$function$
;

CREATE OR REPLACE FUNCTION unipds.gerar_contract_ref(p_fonte_id uuid, p_voomp_venda_id text, p_voomp_contrato_id text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF p_voomp_contrato_id IS NOT NULL THEN
        -- Assinatura: usa o próprio ID do Voomp como referência
        RETURN 'VMP-' || p_voomp_contrato_id;
    ELSE
        -- Venda única: gera referência interna
        RETURN 'UNP-' || UPPER(LEFT(p_fonte_id::TEXT, 8)) || '-' || p_voomp_venda_id;
    END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION unipds.gerar_previsao_parcelas(p_contract_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_contract      RECORD;
    v_data_base     DATE;
    v_data_p1       DATE;
    v_valor_p1      NUMERIC(12,2);
    i               INT;
    v_inseridos     INT := 0;
    v_ref           TEXT;
    v_charge_id     UUID;
    v_valor_previsto NUMERIC(12,2);
    v_data_pag      DATE;
    v_status        TEXT;
BEGIN
    -- Busca P1 paga: data e valor real (valor_oferta_linha ou fallback valor_cobrado)
    SELECT
        ch.data_pagamento,
        COALESCE(ch.valor_oferta_linha, ch.faturamento_total, ch.valor_cobrado)
    INTO v_data_p1, v_valor_p1
    FROM unipds.charges ch
    WHERE ch.contract_id    = p_contract_id
      AND ch.numero_parcela = 1
      AND ch.status         = 'Pago'
      AND ch.valor_cobrado  > 0
    LIMIT 1;

    SELECT * INTO v_contract
    FROM unipds.contracts
    WHERE contract_id = p_contract_id;

    v_data_base := COALESCE(v_data_p1, v_contract.data_primeira_venda);
    v_valor_p1  := COALESCE(v_valor_p1, v_contract.valor_oferta);

    -- Garante que nunca seja NULL
    IF v_valor_p1 IS NULL OR v_valor_p1 = 0 THEN
        v_valor_p1 := v_contract.valor_oferta;
    END IF;

    FOR i IN 1..COALESCE(v_contract.recorrencia_total, 12) LOOP
        v_ref := 'PRV-' || v_contract.contract_ref || '-P' || LPAD(i::TEXT, 2, '0');

        SELECT ch.charge_id, ch.data_pagamento,
               COALESCE(ch.valor_oferta_linha, ch.faturamento_total, ch.valor_cobrado)
        INTO v_charge_id, v_data_pag, v_valor_previsto
        FROM unipds.charges ch
        WHERE ch.contract_id    = p_contract_id
          AND ch.numero_parcela = i
          AND ch.status         = 'Pago'
          AND ch.valor_cobrado  > 0
        LIMIT 1;

        IF v_charge_id IS NULL THEN
            v_valor_previsto := v_valor_p1;
            v_data_pag       := NULL;
            v_status := CASE
                WHEN (v_data_base + ((i - 1) || ' months')::INTERVAL) < CURRENT_DATE
                THEN 'vencido'
                ELSE 'previsto'
            END;
        ELSE
            v_status := 'pago';
            -- Garante valor não nulo mesmo nas pagas
            IF v_valor_previsto IS NULL OR v_valor_previsto = 0 THEN
                v_valor_previsto := v_valor_p1;
            END IF;
        END IF;

        INSERT INTO unipds.previsao_parcelas (
            contract_id, tenant_id, numero_parcela, total_parcelas,
            previsao_ref, valor_previsto, data_prevista, data_pagamento,
            charge_id, status
        ) VALUES (
            p_contract_id,
            v_contract.tenant_id,
            i,
            COALESCE(v_contract.recorrencia_total, 12),
            v_ref,
            v_valor_previsto,
            v_data_base + ((i - 1) || ' months')::INTERVAL,
            v_data_pag,
            v_charge_id,
            v_status
        )
        ON CONFLICT (previsao_ref) DO NOTHING;

        v_inseridos := v_inseridos + 1;
    END LOOP;

    RETURN v_inseridos;
END;
$function$
;

CREATE OR REPLACE FUNCTION unipds.get_parcelas_vencidas(p_contract_id uuid)
 RETURNS TABLE(previsao_id uuid, previsao_ref text, numero_parcela integer, total_parcelas integer, valor_previsto numeric, data_prevista date, status text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'unipds'
AS $function$
    SELECT
        previsao_id,
        previsao_ref,
        numero_parcela,
        total_parcelas,
        valor_previsto,
        data_prevista,
        status
    FROM unipds.previsao_parcelas
    WHERE contract_id = p_contract_id
      AND status = 'vencido'
    ORDER BY data_prevista ASC;
$function$
;

CREATE OR REPLACE FUNCTION unipds.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION unipds.tg_set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION unipds.tg_validar_ingestao_antes_fechamento()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
DECLARE
  v_fontes_ativas    integer;
  v_fontes_completas integer;
BEGIN
  -- Só valida quando há transição para EM_REVISAO ou FECHADO
  IF NEW.estado IN ('EM_REVISAO','FECHADO') 
     AND (TG_OP = 'INSERT' OR OLD.estado IS DISTINCT FROM NEW.estado) THEN

    -- Conta fontes ativas do tenant
    SELECT COUNT(*) INTO v_fontes_ativas
    FROM unipds.fontes 
    WHERE tenant_id = NEW.tenant_id AND ativo = true;

    -- Conta fontes com ingestao COMPLETA para o mês
    SELECT COUNT(*) INTO v_fontes_completas
    FROM unipds.ingestao_status ist
    JOIN unipds.fontes f ON f.fonte_id = ist.fonte_id
    WHERE ist.tenant_id = NEW.tenant_id
      AND ist.ano_mes  = NEW.ano_mes
      AND ist.status   = 'COMPLETA'
      AND f.ativo      = true;

    IF v_fontes_completas < v_fontes_ativas THEN
      RAISE EXCEPTION 
        'Bloqueado: ingestão incompleta. Fontes ativas: %, fontes com ingestão COMPLETA para %: %. Confirme ingestao_status de todas as fontes antes de avançar o fechamento.',
        v_fontes_ativas, NEW.ano_mes, v_fontes_completas;
    END IF;

    -- Carimba timestamp se não existe
    IF NEW.ingestao_validada_em IS NULL THEN
      NEW.ingestao_validada_em := now();
    END IF;
  END IF;

  RETURN NEW;
END;
$function$
;

create or replace view "unipds"."v_cobracas_reais" as  SELECT ch.charge_id,
    ch.contract_id,
    ch.voomp_venda_id,
    ch.numero_parcela,
    ch.forma_pagamento,
    ch.valor_cobrado,
    ch.faturamento_total,
    ch.valor_oferta_linha,
    ch.taxa_voomp,
    ch.comissao_coprodutor,
    ch.valor_recebido,
    ch.metodo_pagamento,
    ch.status,
    ch.data_vencimento,
    ch.data_pagamento,
    ch.data_liberacao_saldo,
    ch.dias_atraso,
    ch.link_boleto,
    ch.chave_pix,
    ch.nota_fiscal,
    ch.cupom,
    ch.created_at,
    c.tenant_id,
    c.student_id,
    c.product_id,
    c.tipo_cobranca,
    c.status_contrato,
    c.contract_ref,
    c.contrato_canonico
   FROM (unipds.charges ch
     JOIN unipds.contracts c ON ((c.contract_id = ch.contract_id)))
  WHERE ((ch.valor_cobrado > (0)::numeric) AND (c.contrato_canonico = true) AND (c.status_contrato <> ALL (ARRAY['failed'::text, 'Recusado'::text])) AND (ch.status <> 'Recusado'::text));


create or replace view "unipds"."v_evasao" as  SELECT ch.charge_id,
    ch.status,
    ch.numero_parcela,
    ch.metodo_pagamento,
    ch.valor_cobrado,
    ch.valor_recebido,
    ch.data_pagamento,
    co.contract_ref,
    co.nome_oferta,
    co.tipo_cobranca,
    co.recorrencia_total,
    co.data_primeira_venda,
    co.tenant_id,
    s.nome,
    s.cpf_cnpj,
    t.nome AS tenant_nome
   FROM (((unipds.charges ch
     JOIN unipds.contracts co ON ((co.contract_id = ch.contract_id)))
     JOIN unipds.students s ON ((s.student_id = co.student_id)))
     JOIN unipds.tenants t ON ((t.tenant_id = co.tenant_id)))
  WHERE (ch.status = ANY (ARRAY['Reembolsado'::text, 'Reembolso Pendente'::text, 'Chargeback'::text]));


create or replace view "unipds"."v_novos_alunos_voomp" as  WITH primeira_parcela_paga AS (
         SELECT DISTINCT ON (ch.contract_id) ch.contract_id,
            ch.charge_id,
            ch.voomp_venda_id,
            ch.valor_recebido,
            ch.valor_cobrado,
            ch.data_pagamento,
            ch.metodo_pagamento,
            ch.status AS charge_status
           FROM unipds.charges ch
          WHERE ((ch.status = ANY (ARRAY['Pago'::text, 'Reembolsado'::text])) AND (COALESCE(ch.numero_parcela, 1) = 1) AND (ch.data_pagamento IS NOT NULL))
          ORDER BY ch.contract_id,
                CASE ch.status
                    WHEN 'Pago'::text THEN 0
                    ELSE 1
                END, ch.data_pagamento
        )
 SELECT c.tenant_id,
    c.contract_id,
    c.fonte_id,
    f.nome AS fonte_nome,
    c.contract_ref,
    c.voomp_contrato_id,
    ppp.voomp_venda_id AS voomp_venda_id_primeira_parcela,
    c.tipo_cobranca,
    c.recorrencia_total,
    c.valor_oferta,
        CASE
            WHEN ((c.tipo_cobranca = 'Assinatura'::text) AND (c.recorrencia_total IS NOT NULL)) THEN (c.valor_oferta * (c.recorrencia_total)::numeric)
            ELSE c.valor_oferta
        END AS valor_contrato_total,
        CASE
            WHEN ((c.tipo_cobranca = 'Assinatura'::text) AND (c.recorrencia_total IS NOT NULL)) THEN (ppp.valor_recebido * (c.recorrencia_total)::numeric)
            ELSE ppp.valor_recebido
        END AS valor_recebido_total,
    c.status_contrato,
    c.data_primeira_venda,
    c.contrato_canonico,
    ppp.charge_id,
    ppp.valor_recebido,
    ppp.valor_cobrado,
    ppp.data_pagamento,
    ppp.metodo_pagamento,
    to_char((ppp.data_pagamento)::timestamp with time zone, 'YYYY-MM'::text) AS ano_mes,
    s.student_id,
    s.cpf_cnpj,
    regexp_replace(COALESCE(s.cpf_cnpj, ''::text), '\D'::text, ''::text, 'g'::text) AS cpf_clean,
    lower(TRIM(BOTH FROM s.email)) AS email_clean,
    s.nome AS aluno_nome,
    lower(translate(regexp_replace(COALESCE(s.nome, ''::text), '[^[:alpha:][:space:]]'::text, ''::text, 'g'::text), 'áéíóúàèìòùâêîôûãõçÁÉÍÓÚÀÈÌÒÙÂÊÎÔÛÃÕÇ'::text, 'aeiouaeiouaeiouaocaeiouaeiouaeiouaoc'::text)) AS aluno_nome_norm,
    regexp_replace(COALESCE(s.telefone, ''::text), '\D'::text, ''::text, 'g'::text) AS telefone_clean,
    p.nome AS produto_nome,
    c.nome_oferta,
        CASE
            WHEN ((c.tipo_cobranca = 'Assinatura'::text) AND (c.recorrencia_total IS NOT NULL)) THEN (ppp.valor_cobrado * (c.recorrencia_total)::numeric)
            ELSE ppp.valor_cobrado
        END AS valor_cobrado_total,
    (ppp.charge_status = 'Reembolsado'::text) AS reembolsado
   FROM ((((unipds.contracts c
     JOIN unipds.fontes f ON ((f.fonte_id = c.fonte_id)))
     JOIN unipds.students s ON ((s.student_id = c.student_id)))
     LEFT JOIN unipds.products p ON ((p.product_id = c.product_id)))
     JOIN primeira_parcela_paga ppp ON ((ppp.contract_id = c.contract_id)))
  WHERE (c.contrato_canonico = true);


create or replace view "unipds"."v_produtos_classificados" as  SELECT product_id,
    voomp_produto_id,
    nome,
    tipo,
        CASE
            WHEN (voomp_produto_id = ANY (ARRAY['7724'::text, '7852'::text, '13761'::text, '13762'::text, '12663'::text])) THEN 'POS_GRADUACAO'::text
            WHEN (voomp_produto_id = ANY (ARRAY['7725'::text, '7856'::text])) THEN 'EXTENSAO'::text
            WHEN (voomp_produto_id = ANY (ARRAY['9752'::text, '12228'::text, '10908'::text])) THEN 'ADMINISTRATIVO'::text
            WHEN (voomp_produto_id = ANY (ARRAY['11957'::text, '11971'::text, '12657'::text, '12658'::text, '12882'::text, '13459'::text, '13764'::text, '13766'::text])) THEN 'POS_GRADUACAO'::text
            WHEN (voomp_produto_id = ANY (ARRAY['11973'::text, '11974'::text, '13497'::text, '14164'::text])) THEN 'EXTENSAO'::text
            WHEN (voomp_produto_id = '11972'::text) THEN 'ADMINISTRATIVO'::text
            ELSE 'OUTRO'::text
        END AS classe
   FROM unipds.products;


create or replace view "unipds"."v_suspeitos_tenant_errado" as  WITH orfaos_pipe AS (
         SELECT pd.tenant_id,
            pd.ano_mes,
            pd.pipe_deal_id,
            pd.pessoa_nome,
            pd.cpf_clean,
            pd.email_clean,
            pd.valor AS pipe_valor,
            pd.funil
           FROM unipds.pipe_deals pd
          WHERE ((pd.status = 'Ganho'::text) AND (NOT (EXISTS ( SELECT 1
                   FROM unipds.conciliacao_links cl
                  WHERE ((cl.tenant_id = pd.tenant_id) AND (cl.pipe_deal_id = pd.pipe_deal_id))))))
        ), orfaos_voomp AS (
         SELECT vna.tenant_id,
            vna.ano_mes,
            vna.contract_id,
            vna.aluno_nome,
            vna.cpf_clean,
            vna.email_clean,
            vna.valor_recebido_total AS voomp_valor
           FROM unipds.v_novos_alunos_voomp vna
          WHERE (NOT (EXISTS ( SELECT 1
                   FROM unipds.conciliacao_links cl
                  WHERE (cl.contract_id = vna.contract_id))))
        ), nomes AS (
         SELECT op.ano_mes,
            op.tenant_id AS tenant_pipe,
            ov.tenant_id AS tenant_voomp,
            op.pipe_deal_id,
            op.funil,
            op.pessoa_nome AS pipe_nome,
            ov.aluno_nome AS voomp_nome,
            op.pipe_valor,
            ov.voomp_valor,
            op.cpf_clean AS pipe_cpf,
            ov.cpf_clean AS voomp_cpf,
            op.email_clean AS pipe_email,
            ov.email_clean AS voomp_email,
            ov.contract_id AS voomp_contract_id,
            lower(translate(regexp_replace(COALESCE(op.pessoa_nome, ''::text), '[^[:alpha:][:space:]]'::text, ''::text, 'g'::text), 'áéíóúàèìòùâêîôûãõçÁÉÍÓÚÀÈÌÒÙÂÊÎÔÛÃÕÇ'::text, 'aeiouaeiouaeiouaocaeiouaeiouaeiouaoc'::text)) AS pipe_nome_norm,
            lower(translate(regexp_replace(COALESCE(ov.aluno_nome, ''::text), '[^[:alpha:][:space:]]'::text, ''::text, 'g'::text), 'áéíóúàèìòùâêîôûãõçÁÉÍÓÚÀÈÌÒÙÂÊÎÔÛÃÕÇ'::text, 'aeiouaeiouaeiouaocaeiouaeiouaeiouaoc'::text)) AS voomp_nome_norm
           FROM (orfaos_pipe op
             JOIN orfaos_voomp ov ON (((op.ano_mes = ov.ano_mes) AND (op.tenant_id <> ov.tenant_id) AND (((op.cpf_clean <> ''::text) AND (op.cpf_clean = ov.cpf_clean)) OR ((op.email_clean <> ''::text) AND (op.email_clean = ov.email_clean))))))
        )
 SELECT ano_mes,
    tenant_pipe,
    tenant_voomp,
    pipe_deal_id,
    funil,
    pipe_nome,
    voomp_nome,
    pipe_valor,
    voomp_valor,
        CASE
            WHEN ((pipe_cpf <> ''::text) AND (pipe_cpf = voomp_cpf)) THEN 'CPF'::text
            ELSE 'EMAIL'::text
        END AS criterio_suspeita,
    (round((public.similarity(pipe_nome_norm, voomp_nome_norm) * (100)::double precision)))::integer AS similaridade_nome,
    voomp_contract_id
   FROM nomes;


create or replace view "unipds"."v_contas_a_receber" as  SELECT s.nome,
    s.cpf_cnpj,
    s.email,
    s.telefone,
    c.contract_ref,
    c.voomp_contrato_id,
    c.tipo_cobranca,
    c.status_contrato,
    p.classe AS tipo_curso,
    pp.previsao_ref,
    pp.numero_parcela,
    pp.total_parcelas,
    pp.valor_previsto,
    pp.data_prevista,
    pp.status AS status_previsao,
    pp.data_pagamento AS data_confirmacao,
    pp.tenant_id,
        CASE pp.tenant_id
            WHEN '70b668e4-be85-459b-8dbb-3876929ac850'::uuid THEN 'Java'::text
            WHEN 'e717e24d-fb30-4ed0-83d3-bb8ea0b66783'::uuid THEN 'IA'::text
            ELSE NULL::text
        END AS tenant_nome
   FROM (((unipds.previsao_parcelas pp
     JOIN unipds.contracts c ON ((c.contract_id = pp.contract_id)))
     JOIN unipds.students s ON ((s.student_id = c.student_id)))
     JOIN unipds.v_produtos_classificados p ON ((p.product_id = c.product_id)))
  WHERE ((pp.status = ANY (ARRAY['previsto'::text, 'vencido'::text, 'pago'::text])) AND (c.contrato_canonico = true) AND (c.status_contrato <> 'Cancelado'::text) AND (p.classe <> 'ADMINISTRATIVO'::text) AND (EXISTS ( SELECT 1
           FROM unipds.charges ch
          WHERE ((ch.contract_id = c.contract_id) AND (ch.status = 'Pago'::text) AND (COALESCE(ch.numero_parcela, 1) = 1)))))
  ORDER BY pp.tenant_id, pp.data_prevista;


create or replace view "unipds"."v_cruzamento_pipe" as  SELECT pd.tenant_id,
    pd.ano_mes,
    pd.pipe_deal_id,
    pd.titulo,
    pd.funil,
    pd.proprietario,
    pd.pessoa_nome,
    pd.cpf_clean AS pipe_cpf_clean,
    pd.email_clean AS pipe_email_clean,
    pd.valor AS pipe_valor,
    pd.ganho_em AS pipe_ganho_em,
    cl.link_id,
    cl.criterio,
    cl.confianca,
    cl.divergencia_valor,
    cl.divergencia_classe,
    cl.cross_tenant,
    cl.contract_id,
    cl.charge_id,
    vna.contract_ref,
    vna.voomp_venda_id_primeira_parcela,
    vna.valor_recebido_total AS voomp_valor_contrato,
    vna.valor_oferta AS voomp_valor_oferta_parcela,
    vna.valor_contrato_total AS voomp_valor_contrato_bruto,
    vna.tipo_cobranca,
    vna.recorrencia_total,
    vna.valor_recebido AS voomp_valor_recebido_1a_parcela,
    vna.data_pagamento AS voomp_data_pagamento,
    vna.aluno_nome AS voomp_aluno_nome,
    vna.cpf_cnpj AS voomp_cpf,
    vna.tenant_id AS voomp_tenant_id,
        CASE
            WHEN (cl.link_id IS NULL) THEN 'ORFAO_PIPE'::text
            ELSE 'CASADO'::text
        END AS status_match,
        CASE
            WHEN (cl.link_id IS NULL) THEN 'SIM'::text
            ELSE 'NAO'::text
        END AS pendente_financeiro,
    vna.valor_cobrado_total AS voomp_valor_cobrado_total,
    vna.reembolsado AS voomp_reembolsado
   FROM ((unipds.pipe_deals pd
     LEFT JOIN unipds.conciliacao_links cl ON (((cl.tenant_id = pd.tenant_id) AND (cl.pipe_deal_id = pd.pipe_deal_id))))
     LEFT JOIN unipds.v_novos_alunos_voomp vna ON ((vna.contract_id = cl.contract_id)))
  WHERE (pd.status = 'Ganho'::text);


create or replace view "unipds"."v_cruzamento_voomp" as  SELECT vna.tenant_id,
    vna.ano_mes,
    vna.contract_id,
    vna.contract_ref,
    vna.voomp_contrato_id,
    vna.voomp_venda_id_primeira_parcela,
    vna.tipo_cobranca,
    vna.recorrencia_total,
    vna.aluno_nome,
    vna.cpf_cnpj,
    vna.email_clean,
    vna.fonte_nome,
    vna.produto_nome,
    vna.valor_oferta AS voomp_valor_oferta_parcela,
    vna.valor_recebido_total AS voomp_valor_contrato,
    vna.valor_contrato_total AS voomp_valor_contrato_bruto,
    vna.valor_recebido AS voomp_valor_recebido_1a_parcela,
    vna.data_pagamento,
    vna.metodo_pagamento,
    cl.link_id,
    cl.pipe_deal_id,
    cl.criterio,
    cl.confianca,
    cl.divergencia_valor,
    cl.divergencia_classe,
    cl.cross_tenant,
    cl.tenant_id AS pipe_tenant_id,
    pd.titulo AS pipe_titulo,
    pd.proprietario AS pipe_proprietario,
    pd.valor AS pipe_valor,
    pd.ganho_em AS pipe_ganho_em,
        CASE
            WHEN (cl.link_id IS NULL) THEN 'ORFAO_VOOMP'::text
            ELSE 'CASADO'::text
        END AS status_match,
        CASE
            WHEN (cl.link_id IS NULL) THEN 'SIM'::text
            ELSE 'NAO'::text
        END AS venda_orfa,
    vna.valor_cobrado_total AS voomp_valor_cobrado_total,
    vna.reembolsado AS voomp_reembolsado
   FROM ((unipds.v_novos_alunos_voomp vna
     LEFT JOIN unipds.conciliacao_links cl ON ((cl.contract_id = vna.contract_id)))
     LEFT JOIN unipds.pipe_deals pd ON (((pd.tenant_id = cl.tenant_id) AND (pd.pipe_deal_id = cl.pipe_deal_id))));


create or replace view "unipds"."v_inadimplencia" as  SELECT s.student_id,
    s.nome,
    s.cpf_cnpj,
    s.email,
    s.telefone,
    c.contract_ref,
    c.tipo_cobranca,
    c.status_contrato,
    p.classe AS tipo_curso,
    pp.previsao_id,
    pp.previsao_ref,
    pp.numero_parcela,
    pp.total_parcelas,
    pp.valor_previsto AS valor_devido,
    pp.data_prevista AS data_vencimento,
    (CURRENT_DATE - pp.data_prevista) AS dias_atraso,
        CASE
            WHEN (((CURRENT_DATE - pp.data_prevista) >= 1) AND ((CURRENT_DATE - pp.data_prevista) <= 30)) THEN '1-30 dias'::text
            WHEN (((CURRENT_DATE - pp.data_prevista) >= 31) AND ((CURRENT_DATE - pp.data_prevista) <= 60)) THEN '31-60 dias'::text
            WHEN (((CURRENT_DATE - pp.data_prevista) >= 61) AND ((CURRENT_DATE - pp.data_prevista) <= 90)) THEN '61-90 dias'::text
            WHEN ((CURRENT_DATE - pp.data_prevista) > 90) THEN '+90 dias'::text
            ELSE NULL::text
        END AS faixa_atraso,
    pp.tenant_id,
        CASE pp.tenant_id
            WHEN '70b668e4-be85-459b-8dbb-3876929ac850'::uuid THEN 'Java'::text
            WHEN 'e717e24d-fb30-4ed0-83d3-bb8ea0b66783'::uuid THEN 'IA'::text
            ELSE NULL::text
        END AS tenant_nome
   FROM (((unipds.previsao_parcelas pp
     JOIN unipds.contracts c ON ((c.contract_id = pp.contract_id)))
     JOIN unipds.students s ON ((s.student_id = c.student_id)))
     JOIN unipds.v_produtos_classificados p ON ((p.product_id = c.product_id)))
  WHERE ((pp.status = 'vencido'::text) AND (c.contrato_canonico = true) AND (c.status_contrato <> 'Cancelado'::text) AND (p.classe <> 'ADMINISTRATIVO'::text) AND (EXISTS ( SELECT 1
           FROM unipds.charges ch
          WHERE ((ch.contract_id = c.contract_id) AND (ch.status = 'Pago'::text) AND (COALESCE(ch.numero_parcela, 1) = 1)))))
  ORDER BY (CURRENT_DATE - pp.data_prevista) DESC;


create or replace view "unipds"."v_matriculas_assinatura" as  WITH parcelas_pagas AS (
         SELECT c.contract_id,
            c.student_id,
            c.product_id,
            c.contract_ref,
            c.voomp_contrato_id,
            c.recorrencia_total,
            c.status_contrato,
            c.tenant_id,
            min(ch.numero_parcela) AS primeira_parcela_paga,
            max(ch.numero_parcela) AS ultima_parcela_paga,
            count(ch.charge_id) AS parcelas_pagas_count,
            max(ch.data_pagamento) AS data_ultimo_pagamento,
            min(ch.data_pagamento) AS data_primeira_pagamento
           FROM (unipds.contracts c
             JOIN unipds.charges ch ON ((ch.contract_id = c.contract_id)))
          WHERE ((c.tipo_cobranca = 'Assinatura'::text) AND (c.contrato_canonico = true) AND (ch.status = 'Pago'::text) AND (ch.valor_cobrado > (0)::numeric))
          GROUP BY c.contract_id, c.student_id, c.product_id, c.contract_ref, c.voomp_contrato_id, c.recorrencia_total, c.status_contrato, c.tenant_id
        )
 SELECT s.student_id,
    s.cpf_cnpj,
    s.nome,
    s.email,
    s.telefone,
    s.uf_origem,
    pp.contract_id,
    pp.contract_ref,
    pp.tenant_id,
    p.classe AS tipo_curso,
    p.nome AS produto_nome,
    pp.primeira_parcela_paga,
    pp.ultima_parcela_paga,
    pp.parcelas_pagas_count,
    pp.recorrencia_total AS total_parcelas_contrato,
    pp.data_primeira_pagamento AS data_matricula,
    pp.data_ultimo_pagamento,
    'ASSINATURA'::text AS modalidade,
    pp.status_contrato,
        CASE
            WHEN (pp.primeira_parcela_paga > 1) THEN true
            ELSE false
        END AS anomalia_sem_p1,
        CASE
            WHEN (pp.recorrencia_total = 10) THEN true
            ELSE false
        END AS anomalia_rec_10
   FROM ((parcelas_pagas pp
     JOIN unipds.students s ON ((s.student_id = pp.student_id)))
     JOIN unipds.v_produtos_classificados p ON ((p.product_id = pp.product_id)))
  WHERE (p.classe <> 'ADMINISTRATIVO'::text);


create or replace view "unipds"."v_matriculas_unico" as  SELECT s.student_id,
    s.cpf_cnpj,
    s.nome,
    s.email,
    s.telefone,
    s.uf_origem,
    c.contract_id,
    c.contract_ref,
    c.tenant_id,
    p.classe AS tipo_curso,
    p.nome AS produto_nome,
    ch.charge_id,
    ch.valor_cobrado,
    ch.metodo_pagamento,
    ch.data_pagamento AS data_matricula,
    'UNICO'::text AS modalidade,
    NULL::integer AS parcela_atual,
    NULL::integer AS total_parcelas,
    c.status_contrato
   FROM (((unipds.contracts c
     JOIN unipds.students s ON ((s.student_id = c.student_id)))
     JOIN unipds.charges ch ON ((ch.contract_id = c.contract_id)))
     JOIN unipds.v_produtos_classificados p ON ((p.product_id = c.product_id)))
  WHERE ((c.tipo_cobranca = 'Único'::text) AND (ch.status = 'Pago'::text) AND (ch.valor_cobrado > (0)::numeric) AND (p.classe <> 'ADMINISTRATIVO'::text) AND (c.contrato_canonico = true));


create or replace view "unipds"."v_matriculas_ativas" as  SELECT v_matriculas_unico.student_id,
    v_matriculas_unico.cpf_cnpj,
    v_matriculas_unico.nome,
    v_matriculas_unico.email,
    v_matriculas_unico.telefone,
    v_matriculas_unico.uf_origem,
    v_matriculas_unico.contract_id,
    v_matriculas_unico.contract_ref,
    v_matriculas_unico.tenant_id,
    v_matriculas_unico.tipo_curso,
    v_matriculas_unico.produto_nome,
    v_matriculas_unico.modalidade,
    v_matriculas_unico.data_matricula,
    v_matriculas_unico.status_contrato,
    false AS anomalia_sem_p1,
    false AS anomalia_rec_10
   FROM unipds.v_matriculas_unico
UNION ALL
 SELECT v_matriculas_assinatura.student_id,
    v_matriculas_assinatura.cpf_cnpj,
    v_matriculas_assinatura.nome,
    v_matriculas_assinatura.email,
    v_matriculas_assinatura.telefone,
    v_matriculas_assinatura.uf_origem,
    v_matriculas_assinatura.contract_id,
    v_matriculas_assinatura.contract_ref,
    v_matriculas_assinatura.tenant_id,
    v_matriculas_assinatura.tipo_curso,
    v_matriculas_assinatura.produto_nome,
    v_matriculas_assinatura.modalidade,
    v_matriculas_assinatura.data_matricula,
    v_matriculas_assinatura.status_contrato,
    v_matriculas_assinatura.anomalia_sem_p1,
    v_matriculas_assinatura.anomalia_rec_10
   FROM unipds.v_matriculas_assinatura;


create or replace view "unipds"."v_resumo_executivo" as  SELECT
        CASE
            WHEN (tenant_id = '70b668e4-be85-459b-8dbb-3876929ac850'::uuid) THEN 'Java'::text
            WHEN (tenant_id = 'e717e24d-fb30-4ed0-83d3-bb8ea0b66783'::uuid) THEN 'IA'::text
            ELSE NULL::text
        END AS tenant,
    tipo_curso,
    modalidade,
    count(DISTINCT student_id) AS alunos_ativos,
    count(DISTINCT contract_id) AS contratos_ativos
   FROM unipds.v_matriculas_ativas
  GROUP BY tenant_id, tipo_curso, modalidade
  ORDER BY
        CASE
            WHEN (tenant_id = '70b668e4-be85-459b-8dbb-3876929ac850'::uuid) THEN 'Java'::text
            WHEN (tenant_id = 'e717e24d-fb30-4ed0-83d3-bb8ea0b66783'::uuid) THEN 'IA'::text
            ELSE NULL::text
        END, tipo_curso, modalidade;


grant insert on table "cobranca"."cobranca_casos" to "anon";

grant select on table "cobranca"."cobranca_casos" to "anon";

grant update on table "cobranca"."cobranca_casos" to "anon";

grant insert on table "cobranca"."cobranca_casos" to "authenticated";

grant select on table "cobranca"."cobranca_casos" to "authenticated";

grant update on table "cobranca"."cobranca_casos" to "authenticated";

grant insert on table "cobranca"."cobranca_interacoes" to "anon";

grant select on table "cobranca"."cobranca_interacoes" to "anon";

grant update on table "cobranca"."cobranca_interacoes" to "anon";

grant insert on table "cobranca"."cobranca_interacoes" to "authenticated";

grant select on table "cobranca"."cobranca_interacoes" to "authenticated";

grant update on table "cobranca"."cobranca_interacoes" to "authenticated";

grant insert on table "cobranca"."cobranca_negociacoes" to "anon";

grant select on table "cobranca"."cobranca_negociacoes" to "anon";

grant update on table "cobranca"."cobranca_negociacoes" to "anon";

grant insert on table "cobranca"."cobranca_negociacoes" to "authenticated";

grant select on table "cobranca"."cobranca_negociacoes" to "authenticated";

grant update on table "cobranca"."cobranca_negociacoes" to "authenticated";

grant select on table "financeiro"."lancamentos" to "anon";

grant select on table "financeiro"."lancamentos" to "authenticated";

grant delete on table "financeiro"."lancamentos" to "service_role";

grant insert on table "financeiro"."lancamentos" to "service_role";

grant references on table "financeiro"."lancamentos" to "service_role";

grant select on table "financeiro"."lancamentos" to "service_role";

grant trigger on table "financeiro"."lancamentos" to "service_role";

grant truncate on table "financeiro"."lancamentos" to "service_role";

grant update on table "financeiro"."lancamentos" to "service_role";

grant select on table "financeiro"."mapeamento_categorias" to "anon";

grant select on table "financeiro"."mapeamento_categorias" to "authenticated";

grant delete on table "financeiro"."mapeamento_categorias" to "service_role";

grant insert on table "financeiro"."mapeamento_categorias" to "service_role";

grant references on table "financeiro"."mapeamento_categorias" to "service_role";

grant select on table "financeiro"."mapeamento_categorias" to "service_role";

grant trigger on table "financeiro"."mapeamento_categorias" to "service_role";

grant truncate on table "financeiro"."mapeamento_categorias" to "service_role";

grant update on table "financeiro"."mapeamento_categorias" to "service_role";

grant select on table "financeiro"."sync_log" to "anon";

grant select on table "financeiro"."sync_log" to "authenticated";

grant delete on table "financeiro"."sync_log" to "service_role";

grant insert on table "financeiro"."sync_log" to "service_role";

grant references on table "financeiro"."sync_log" to "service_role";

grant select on table "financeiro"."sync_log" to "service_role";

grant trigger on table "financeiro"."sync_log" to "service_role";

grant truncate on table "financeiro"."sync_log" to "service_role";

grant update on table "financeiro"."sync_log" to "service_role";

grant select on table "unipds"."charges" to "anon";

grant delete on table "unipds"."charges" to "authenticated";

grant insert on table "unipds"."charges" to "authenticated";

grant select on table "unipds"."charges" to "authenticated";

grant update on table "unipds"."charges" to "authenticated";

grant delete on table "unipds"."charges" to "service_role";

grant insert on table "unipds"."charges" to "service_role";

grant references on table "unipds"."charges" to "service_role";

grant select on table "unipds"."charges" to "service_role";

grant trigger on table "unipds"."charges" to "service_role";

grant truncate on table "unipds"."charges" to "service_role";

grant update on table "unipds"."charges" to "service_role";

grant delete on table "unipds"."conciliacao_links" to "authenticated";

grant insert on table "unipds"."conciliacao_links" to "authenticated";

grant select on table "unipds"."conciliacao_links" to "authenticated";

grant update on table "unipds"."conciliacao_links" to "authenticated";

grant delete on table "unipds"."conciliacao_links" to "service_role";

grant insert on table "unipds"."conciliacao_links" to "service_role";

grant references on table "unipds"."conciliacao_links" to "service_role";

grant select on table "unipds"."conciliacao_links" to "service_role";

grant trigger on table "unipds"."conciliacao_links" to "service_role";

grant truncate on table "unipds"."conciliacao_links" to "service_role";

grant update on table "unipds"."conciliacao_links" to "service_role";

grant delete on table "unipds"."conciliacao_runs" to "authenticated";

grant insert on table "unipds"."conciliacao_runs" to "authenticated";

grant select on table "unipds"."conciliacao_runs" to "authenticated";

grant update on table "unipds"."conciliacao_runs" to "authenticated";

grant delete on table "unipds"."conciliacao_runs" to "service_role";

grant insert on table "unipds"."conciliacao_runs" to "service_role";

grant references on table "unipds"."conciliacao_runs" to "service_role";

grant select on table "unipds"."conciliacao_runs" to "service_role";

grant trigger on table "unipds"."conciliacao_runs" to "service_role";

grant truncate on table "unipds"."conciliacao_runs" to "service_role";

grant update on table "unipds"."conciliacao_runs" to "service_role";

grant select on table "unipds"."contracts" to "anon";

grant delete on table "unipds"."contracts" to "authenticated";

grant insert on table "unipds"."contracts" to "authenticated";

grant select on table "unipds"."contracts" to "authenticated";

grant update on table "unipds"."contracts" to "authenticated";

grant delete on table "unipds"."contracts" to "service_role";

grant insert on table "unipds"."contracts" to "service_role";

grant references on table "unipds"."contracts" to "service_role";

grant select on table "unipds"."contracts" to "service_role";

grant trigger on table "unipds"."contracts" to "service_role";

grant truncate on table "unipds"."contracts" to "service_role";

grant update on table "unipds"."contracts" to "service_role";

grant delete on table "unipds"."fechamentos_mensais" to "authenticated";

grant insert on table "unipds"."fechamentos_mensais" to "authenticated";

grant select on table "unipds"."fechamentos_mensais" to "authenticated";

grant update on table "unipds"."fechamentos_mensais" to "authenticated";

grant delete on table "unipds"."fechamentos_mensais" to "service_role";

grant insert on table "unipds"."fechamentos_mensais" to "service_role";

grant references on table "unipds"."fechamentos_mensais" to "service_role";

grant select on table "unipds"."fechamentos_mensais" to "service_role";

grant trigger on table "unipds"."fechamentos_mensais" to "service_role";

grant truncate on table "unipds"."fechamentos_mensais" to "service_role";

grant update on table "unipds"."fechamentos_mensais" to "service_role";

grant select on table "unipds"."fontes" to "anon";

grant delete on table "unipds"."fontes" to "authenticated";

grant insert on table "unipds"."fontes" to "authenticated";

grant select on table "unipds"."fontes" to "authenticated";

grant update on table "unipds"."fontes" to "authenticated";

grant delete on table "unipds"."fontes" to "service_role";

grant insert on table "unipds"."fontes" to "service_role";

grant references on table "unipds"."fontes" to "service_role";

grant select on table "unipds"."fontes" to "service_role";

grant trigger on table "unipds"."fontes" to "service_role";

grant truncate on table "unipds"."fontes" to "service_role";

grant update on table "unipds"."fontes" to "service_role";

grant delete on table "unipds"."ingestao_status" to "authenticated";

grant insert on table "unipds"."ingestao_status" to "authenticated";

grant select on table "unipds"."ingestao_status" to "authenticated";

grant update on table "unipds"."ingestao_status" to "authenticated";

grant delete on table "unipds"."ingestao_status" to "service_role";

grant insert on table "unipds"."ingestao_status" to "service_role";

grant references on table "unipds"."ingestao_status" to "service_role";

grant select on table "unipds"."ingestao_status" to "service_role";

grant trigger on table "unipds"."ingestao_status" to "service_role";

grant truncate on table "unipds"."ingestao_status" to "service_role";

grant update on table "unipds"."ingestao_status" to "service_role";

grant select on table "unipds"."payment_attempts" to "anon";

grant delete on table "unipds"."payment_attempts" to "authenticated";

grant insert on table "unipds"."payment_attempts" to "authenticated";

grant select on table "unipds"."payment_attempts" to "authenticated";

grant update on table "unipds"."payment_attempts" to "authenticated";

grant delete on table "unipds"."payment_attempts" to "service_role";

grant insert on table "unipds"."payment_attempts" to "service_role";

grant references on table "unipds"."payment_attempts" to "service_role";

grant select on table "unipds"."payment_attempts" to "service_role";

grant trigger on table "unipds"."payment_attempts" to "service_role";

grant truncate on table "unipds"."payment_attempts" to "service_role";

grant update on table "unipds"."payment_attempts" to "service_role";

grant delete on table "unipds"."pipe_deals" to "authenticated";

grant insert on table "unipds"."pipe_deals" to "authenticated";

grant select on table "unipds"."pipe_deals" to "authenticated";

grant update on table "unipds"."pipe_deals" to "authenticated";

grant delete on table "unipds"."pipe_deals" to "service_role";

grant insert on table "unipds"."pipe_deals" to "service_role";

grant references on table "unipds"."pipe_deals" to "service_role";

grant select on table "unipds"."pipe_deals" to "service_role";

grant trigger on table "unipds"."pipe_deals" to "service_role";

grant truncate on table "unipds"."pipe_deals" to "service_role";

grant update on table "unipds"."pipe_deals" to "service_role";

grant select on table "unipds"."previsao_parcelas" to "anon";

grant delete on table "unipds"."previsao_parcelas" to "authenticated";

grant insert on table "unipds"."previsao_parcelas" to "authenticated";

grant select on table "unipds"."previsao_parcelas" to "authenticated";

grant update on table "unipds"."previsao_parcelas" to "authenticated";

grant delete on table "unipds"."previsao_parcelas" to "service_role";

grant insert on table "unipds"."previsao_parcelas" to "service_role";

grant references on table "unipds"."previsao_parcelas" to "service_role";

grant select on table "unipds"."previsao_parcelas" to "service_role";

grant trigger on table "unipds"."previsao_parcelas" to "service_role";

grant truncate on table "unipds"."previsao_parcelas" to "service_role";

grant update on table "unipds"."previsao_parcelas" to "service_role";

grant select on table "unipds"."products" to "anon";

grant delete on table "unipds"."products" to "authenticated";

grant insert on table "unipds"."products" to "authenticated";

grant select on table "unipds"."products" to "authenticated";

grant update on table "unipds"."products" to "authenticated";

grant delete on table "unipds"."products" to "service_role";

grant insert on table "unipds"."products" to "service_role";

grant references on table "unipds"."products" to "service_role";

grant select on table "unipds"."products" to "service_role";

grant trigger on table "unipds"."products" to "service_role";

grant truncate on table "unipds"."products" to "service_role";

grant update on table "unipds"."products" to "service_role";

grant select on table "unipds"."raw_imports" to "anon";

grant delete on table "unipds"."raw_imports" to "authenticated";

grant insert on table "unipds"."raw_imports" to "authenticated";

grant select on table "unipds"."raw_imports" to "authenticated";

grant update on table "unipds"."raw_imports" to "authenticated";

grant delete on table "unipds"."raw_imports" to "service_role";

grant insert on table "unipds"."raw_imports" to "service_role";

grant references on table "unipds"."raw_imports" to "service_role";

grant select on table "unipds"."raw_imports" to "service_role";

grant trigger on table "unipds"."raw_imports" to "service_role";

grant truncate on table "unipds"."raw_imports" to "service_role";

grant update on table "unipds"."raw_imports" to "service_role";

grant select on table "unipds"."raw_lines" to "anon";

grant delete on table "unipds"."raw_lines" to "authenticated";

grant insert on table "unipds"."raw_lines" to "authenticated";

grant select on table "unipds"."raw_lines" to "authenticated";

grant update on table "unipds"."raw_lines" to "authenticated";

grant delete on table "unipds"."raw_lines" to "service_role";

grant insert on table "unipds"."raw_lines" to "service_role";

grant references on table "unipds"."raw_lines" to "service_role";

grant select on table "unipds"."raw_lines" to "service_role";

grant trigger on table "unipds"."raw_lines" to "service_role";

grant truncate on table "unipds"."raw_lines" to "service_role";

grant update on table "unipds"."raw_lines" to "service_role";

grant select on table "unipds"."refunds" to "anon";

grant delete on table "unipds"."refunds" to "authenticated";

grant insert on table "unipds"."refunds" to "authenticated";

grant select on table "unipds"."refunds" to "authenticated";

grant update on table "unipds"."refunds" to "authenticated";

grant delete on table "unipds"."refunds" to "service_role";

grant insert on table "unipds"."refunds" to "service_role";

grant references on table "unipds"."refunds" to "service_role";

grant select on table "unipds"."refunds" to "service_role";

grant trigger on table "unipds"."refunds" to "service_role";

grant truncate on table "unipds"."refunds" to "service_role";

grant update on table "unipds"."refunds" to "service_role";

grant select on table "unipds"."students" to "anon";

grant delete on table "unipds"."students" to "authenticated";

grant insert on table "unipds"."students" to "authenticated";

grant select on table "unipds"."students" to "authenticated";

grant update on table "unipds"."students" to "authenticated";

grant delete on table "unipds"."students" to "service_role";

grant insert on table "unipds"."students" to "service_role";

grant references on table "unipds"."students" to "service_role";

grant select on table "unipds"."students" to "service_role";

grant trigger on table "unipds"."students" to "service_role";

grant truncate on table "unipds"."students" to "service_role";

grant update on table "unipds"."students" to "service_role";

grant select on table "unipds"."tenants" to "anon";

grant delete on table "unipds"."tenants" to "authenticated";

grant insert on table "unipds"."tenants" to "authenticated";

grant select on table "unipds"."tenants" to "authenticated";

grant update on table "unipds"."tenants" to "authenticated";

grant delete on table "unipds"."tenants" to "service_role";

grant insert on table "unipds"."tenants" to "service_role";

grant references on table "unipds"."tenants" to "service_role";

grant select on table "unipds"."tenants" to "service_role";

grant trigger on table "unipds"."tenants" to "service_role";

grant truncate on table "unipds"."tenants" to "service_role";

grant update on table "unipds"."tenants" to "service_role";


  create policy "tenant_isolation"
  on "cobranca"."cobranca_casos"
  as permissive
  for all
  to public
using ((tenant_id = (((auth.jwt() -> 'user_metadata'::text) ->> 'tenant_id'::text))::uuid));



  create policy "tenant_isolation"
  on "cobranca"."cobranca_interacoes"
  as permissive
  for all
  to public
using ((caso_id IN ( SELECT cobranca_casos.caso_id
   FROM cobranca.cobranca_casos
  WHERE (cobranca_casos.tenant_id = (((auth.jwt() -> 'user_metadata'::text) ->> 'tenant_id'::text))::uuid))));



  create policy "tenant_isolation"
  on "cobranca"."cobranca_negociacoes"
  as permissive
  for all
  to public
using ((caso_id IN ( SELECT cobranca_casos.caso_id
   FROM cobranca.cobranca_casos
  WHERE (cobranca_casos.tenant_id = (((auth.jwt() -> 'user_metadata'::text) ->> 'tenant_id'::text))::uuid))));



  create policy "read_access_authenticated"
  on "financeiro"."lancamentos"
  as permissive
  for select
  to authenticated
using (true);



  create policy "service_role_full_access"
  on "financeiro"."lancamentos"
  as permissive
  for all
  to service_role
using (true)
with check (true);



  create policy "read_access_mapeamento"
  on "financeiro"."mapeamento_categorias"
  as permissive
  for select
  to authenticated
using (true);



  create policy "service_role_full_access_mapeamento"
  on "financeiro"."mapeamento_categorias"
  as permissive
  for all
  to service_role
using (true)
with check (true);



  create policy "read_access_sync_log"
  on "financeiro"."sync_log"
  as permissive
  for select
  to authenticated
using (true);



  create policy "service_role_full_access_sync_log"
  on "financeiro"."sync_log"
  as permissive
  for all
  to service_role
using (true)
with check (true);



  create policy "authenticated_access"
  on "unipds"."charges"
  as permissive
  for all
  to public
using ((auth.role() = 'authenticated'::text));



  create policy "authenticated_access"
  on "unipds"."conciliacao_links"
  as permissive
  for all
  to public
using ((auth.role() = 'authenticated'::text));



  create policy "authenticated_access"
  on "unipds"."conciliacao_runs"
  as permissive
  for all
  to public
using ((auth.role() = 'authenticated'::text));



  create policy "authenticated_access"
  on "unipds"."contracts"
  as permissive
  for all
  to public
using ((auth.role() = 'authenticated'::text));



  create policy "authenticated_access"
  on "unipds"."fechamentos_mensais"
  as permissive
  for all
  to public
using ((auth.role() = 'authenticated'::text));



  create policy "authenticated_access"
  on "unipds"."fontes"
  as permissive
  for all
  to public
using ((auth.role() = 'authenticated'::text));



  create policy "authenticated_access"
  on "unipds"."ingestao_status"
  as permissive
  for all
  to public
using ((auth.role() = 'authenticated'::text));



  create policy "authenticated_access"
  on "unipds"."payment_attempts"
  as permissive
  for all
  to public
using ((auth.role() = 'authenticated'::text));



  create policy "authenticated_access"
  on "unipds"."pipe_deals"
  as permissive
  for all
  to public
using ((auth.role() = 'authenticated'::text));



  create policy "authenticated_access"
  on "unipds"."previsao_parcelas"
  as permissive
  for all
  to public
using ((auth.role() = 'authenticated'::text));



  create policy "authenticated_access"
  on "unipds"."products"
  as permissive
  for all
  to public
using ((auth.role() = 'authenticated'::text));



  create policy "authenticated_access"
  on "unipds"."raw_imports"
  as permissive
  for all
  to public
using ((auth.role() = 'authenticated'::text));



  create policy "authenticated_access"
  on "unipds"."raw_lines"
  as permissive
  for all
  to public
using ((auth.role() = 'authenticated'::text));



  create policy "authenticated_access"
  on "unipds"."refunds"
  as permissive
  for all
  to public
using ((auth.role() = 'authenticated'::text));



  create policy "authenticated_access"
  on "unipds"."students"
  as permissive
  for all
  to public
using ((auth.role() = 'authenticated'::text));



  create policy "authenticated_access"
  on "unipds"."tenants"
  as permissive
  for all
  to public
using ((auth.role() = 'authenticated'::text));


CREATE TRIGGER trg_casos_encerramento BEFORE UPDATE ON cobranca.cobranca_casos FOR EACH ROW EXECUTE FUNCTION cobranca.registrar_encerramento();

CREATE TRIGGER trg_casos_updated_at BEFORE UPDATE ON cobranca.cobranca_casos FOR EACH ROW EXECUTE FUNCTION cobranca.set_updated_at();

CREATE TRIGGER trg_interacao_atualiza_caso AFTER INSERT ON cobranca.cobranca_interacoes FOR EACH ROW EXECUTE FUNCTION cobranca.atualizar_ultima_interacao();

CREATE TRIGGER trg_negociacoes_updated_at BEFORE UPDATE ON cobranca.cobranca_negociacoes FOR EACH ROW EXECUTE FUNCTION cobranca.set_updated_at();

CREATE TRIGGER set_updated_at BEFORE UPDATE ON financeiro.lancamentos FOR EACH ROW EXECUTE FUNCTION financeiro.trigger_set_updated_at();

CREATE TRIGGER trg_links_updated_at BEFORE UPDATE ON unipds.conciliacao_links FOR EACH ROW EXECUTE FUNCTION unipds.tg_set_updated_at();

CREATE TRIGGER trg_contracts_updated_at BEFORE UPDATE ON unipds.contracts FOR EACH ROW EXECUTE FUNCTION unipds.set_updated_at();

CREATE TRIGGER trg_fechamentos_updated_at BEFORE UPDATE ON unipds.fechamentos_mensais FOR EACH ROW EXECUTE FUNCTION unipds.tg_set_updated_at();

CREATE TRIGGER trg_validar_ingestao_fechamento BEFORE INSERT OR UPDATE ON unipds.fechamentos_mensais FOR EACH ROW EXECUTE FUNCTION unipds.tg_validar_ingestao_antes_fechamento();

CREATE TRIGGER trg_ingestao_status_updated_at BEFORE UPDATE ON unipds.ingestao_status FOR EACH ROW EXECUTE FUNCTION unipds.tg_set_updated_at();

CREATE TRIGGER trg_pipe_deals_updated_at BEFORE UPDATE ON unipds.pipe_deals FOR EACH ROW EXECUTE FUNCTION unipds.tg_set_updated_at();

CREATE TRIGGER trg_previsao_updated_at BEFORE UPDATE ON unipds.previsao_parcelas FOR EACH ROW EXECUTE FUNCTION unipds.set_updated_at();

CREATE TRIGGER trg_products_updated_at BEFORE UPDATE ON unipds.products FOR EACH ROW EXECUTE FUNCTION unipds.set_updated_at();

CREATE TRIGGER trg_students_updated_at BEFORE UPDATE ON unipds.students FOR EACH ROW EXECUTE FUNCTION unipds.set_updated_at();


-- ============================================================
-- COMPLEMENTO: Views (extraídas via pg_get_viewdef da produção)
-- Ordem topológica: nível 0 → 1 → 2 → 3
-- ============================================================

CREATE OR REPLACE VIEW unipds.v_produtos_classificados AS SELECT product_id,
    voomp_produto_id,
    nome,
    tipo,
        CASE
            WHEN voomp_produto_id = ANY (ARRAY['7724'::text, '7852'::text, '13761'::text, '13762'::text, '12663'::text]) THEN 'POS_GRADUACAO'::text
            WHEN voomp_produto_id = ANY (ARRAY['7725'::text, '7856'::text]) THEN 'EXTENSAO'::text
            WHEN voomp_produto_id = ANY (ARRAY['9752'::text, '12228'::text, '10908'::text]) THEN 'ADMINISTRATIVO'::text
            WHEN voomp_produto_id = ANY (ARRAY['11957'::text, '11971'::text, '12657'::text, '12658'::text, '12882'::text, '13459'::text, '13764'::text, '13766'::text]) THEN 'POS_GRADUACAO'::text
            WHEN voomp_produto_id = ANY (ARRAY['11973'::text, '11974'::text, '13497'::text, '14164'::text]) THEN 'EXTENSAO'::text
            WHEN voomp_produto_id = '11972'::text THEN 'ADMINISTRATIVO'::text
            ELSE 'OUTRO'::text
        END AS classe
   FROM unipds.products;

CREATE OR REPLACE VIEW unipds.v_novos_alunos_voomp AS WITH primeira_parcela_paga AS (
         SELECT DISTINCT ON (ch.contract_id) ch.contract_id,
            ch.charge_id,
            ch.voomp_venda_id,
            ch.valor_recebido,
            ch.valor_cobrado,
            ch.data_pagamento,
            ch.metodo_pagamento,
            ch.status AS charge_status
           FROM unipds.charges ch
          WHERE (ch.status = ANY (ARRAY['Pago'::text, 'Reembolsado'::text])) AND COALESCE(ch.numero_parcela, 1) = 1 AND ch.data_pagamento IS NOT NULL
          ORDER BY ch.contract_id, (
                CASE ch.status
                    WHEN 'Pago'::text THEN 0
                    ELSE 1
                END), ch.data_pagamento
        )
 SELECT c.tenant_id,
    c.contract_id,
    c.fonte_id,
    f.nome AS fonte_nome,
    c.contract_ref,
    c.voomp_contrato_id,
    ppp.voomp_venda_id AS voomp_venda_id_primeira_parcela,
    c.tipo_cobranca,
    c.recorrencia_total,
    c.valor_oferta,
        CASE
            WHEN c.tipo_cobranca = 'Assinatura'::text AND c.recorrencia_total IS NOT NULL THEN c.valor_oferta * c.recorrencia_total::numeric
            ELSE c.valor_oferta
        END AS valor_contrato_total,
        CASE
            WHEN c.tipo_cobranca = 'Assinatura'::text AND c.recorrencia_total IS NOT NULL THEN ppp.valor_recebido * c.recorrencia_total::numeric
            ELSE ppp.valor_recebido
        END AS valor_recebido_total,
    c.status_contrato,
    c.data_primeira_venda,
    c.contrato_canonico,
    ppp.charge_id,
    ppp.valor_recebido,
    ppp.valor_cobrado,
    ppp.data_pagamento,
    ppp.metodo_pagamento,
    to_char(ppp.data_pagamento::timestamp with time zone, 'YYYY-MM'::text) AS ano_mes,
    s.student_id,
    s.cpf_cnpj,
    regexp_replace(COALESCE(s.cpf_cnpj, ''::text), '\D'::text, ''::text, 'g'::text) AS cpf_clean,
    lower(TRIM(BOTH FROM s.email)) AS email_clean,
    s.nome AS aluno_nome,
    lower(translate(regexp_replace(COALESCE(s.nome, ''::text), '[^[:alpha:][:space:]]'::text, ''::text, 'g'::text), 'áéíóúàèìòùâêîôûãõçÁÉÍÓÚÀÈÌÒÙÂÊÎÔÛÃÕÇ'::text, 'aeiouaeiouaeiouaocaeiouaeiouaeiouaoc'::text)) AS aluno_nome_norm,
    regexp_replace(COALESCE(s.telefone, ''::text), '\D'::text, ''::text, 'g'::text) AS telefone_clean,
    p.nome AS produto_nome,
    c.nome_oferta,
        CASE
            WHEN c.tipo_cobranca = 'Assinatura'::text AND c.recorrencia_total IS NOT NULL THEN ppp.valor_cobrado * c.recorrencia_total::numeric
            ELSE ppp.valor_cobrado
        END AS valor_cobrado_total,
    ppp.charge_status = 'Reembolsado'::text AS reembolsado
   FROM unipds.contracts c
     JOIN unipds.fontes f ON f.fonte_id = c.fonte_id
     JOIN unipds.students s ON s.student_id = c.student_id
     LEFT JOIN unipds.products p ON p.product_id = c.product_id
     JOIN primeira_parcela_paga ppp ON ppp.contract_id = c.contract_id
  WHERE c.contrato_canonico = true;

CREATE OR REPLACE VIEW unipds.v_evasao AS SELECT ch.charge_id,
    ch.status,
    ch.numero_parcela,
    ch.metodo_pagamento,
    ch.valor_cobrado,
    ch.valor_recebido,
    ch.data_pagamento,
    co.contract_ref,
    co.nome_oferta,
    co.tipo_cobranca,
    co.recorrencia_total,
    co.data_primeira_venda,
    co.tenant_id,
    s.nome,
    s.cpf_cnpj,
    t.nome AS tenant_nome
   FROM unipds.charges ch
     JOIN unipds.contracts co ON co.contract_id = ch.contract_id
     JOIN unipds.students s ON s.student_id = co.student_id
     JOIN unipds.tenants t ON t.tenant_id = co.tenant_id
  WHERE ch.status = ANY (ARRAY['Reembolsado'::text, 'Reembolso Pendente'::text, 'Chargeback'::text]);

CREATE OR REPLACE VIEW unipds.v_cobracas_reais AS SELECT ch.charge_id,
    ch.contract_id,
    ch.voomp_venda_id,
    ch.numero_parcela,
    ch.forma_pagamento,
    ch.valor_cobrado,
    ch.faturamento_total,
    ch.valor_oferta_linha,
    ch.taxa_voomp,
    ch.comissao_coprodutor,
    ch.valor_recebido,
    ch.metodo_pagamento,
    ch.status,
    ch.data_vencimento,
    ch.data_pagamento,
    ch.data_liberacao_saldo,
    ch.dias_atraso,
    ch.link_boleto,
    ch.chave_pix,
    ch.nota_fiscal,
    ch.cupom,
    ch.created_at,
    c.tenant_id,
    c.student_id,
    c.product_id,
    c.tipo_cobranca,
    c.status_contrato,
    c.contract_ref,
    c.contrato_canonico
   FROM unipds.charges ch
     JOIN unipds.contracts c ON c.contract_id = ch.contract_id
  WHERE ch.valor_cobrado > 0::numeric AND c.contrato_canonico = true AND (c.status_contrato <> ALL (ARRAY['failed'::text, 'Recusado'::text])) AND ch.status <> 'Recusado'::text;

CREATE OR REPLACE VIEW cobranca.v_casos_completos AS SELECT cc.caso_id,
    cc.contract_id,
    cc.tenant_id,
        CASE
            WHEN cc.tenant_id = '70b668e4-be85-459b-8dbb-3876929ac850'::uuid THEN 'Java'::text
            WHEN cc.tenant_id = 'e717e24d-fb30-4ed0-83d3-bb8ea0b66783'::uuid THEN 'IA'::text
            ELSE NULL::text
        END AS tenant_nome,
    cc.status,
    cc.faixa_aging,
    cc.valor_total_aberto,
    cc.parcelas_vencidas,
    cc.valor_revertido,
    cc.data_pagamento_revertido,
    cc.responsavel,
    cc.data_abertura,
    cc.data_ultima_interacao,
    cc.data_encerramento,
    cc.observacao_encerramento,
    c.contract_ref,
    c.voomp_contrato_id,
    c.status_contrato,
    c.tipo_cobranca,
    s.nome,
    s.cpf_cnpj,
    s.email,
    s.telefone,
    ( SELECT count(*) AS count
           FROM cobranca.cobranca_interacoes ci
          WHERE ci.caso_id = cc.caso_id) AS total_contatos,
    ( SELECT count(*) AS count
           FROM cobranca.cobranca_interacoes ci
          WHERE ci.caso_id = cc.caso_id AND ci.houve_retorno = true) AS total_retornos,
    ( SELECT max(ci.data_contato) AS max
           FROM cobranca.cobranca_interacoes ci
          WHERE ci.caso_id = cc.caso_id) AS data_ultimo_contato,
    ( SELECT cn.status
           FROM cobranca.cobranca_negociacoes cn
          WHERE cn.caso_id = cc.caso_id
          ORDER BY cn.created_at DESC
         LIMIT 1) AS status_negociacao,
    ( SELECT cn.valor_total_acordado
           FROM cobranca.cobranca_negociacoes cn
          WHERE cn.caso_id = cc.caso_id
          ORDER BY cn.created_at DESC
         LIMIT 1) AS valor_negociado,
    ( SELECT cn.data_primeiro_vencimento
           FROM cobranca.cobranca_negociacoes cn
          WHERE cn.caso_id = cc.caso_id
          ORDER BY cn.created_at DESC
         LIMIT 1) AS proximo_vencimento_acordo
   FROM cobranca.cobranca_casos cc
     JOIN unipds.contracts c ON c.contract_id = cc.contract_id
     JOIN unipds.students s ON s.student_id = c.student_id
  ORDER BY cc.faixa_aging DESC, cc.valor_total_aberto DESC;

CREATE OR REPLACE VIEW cobranca.v_kpis AS SELECT count(*) AS total_casos,
    count(*) FILTER (WHERE status = 'em_aberto'::cobranca.status_caso) AS casos_em_aberto,
    count(*) FILTER (WHERE status = 'em_contato'::cobranca.status_caso) AS casos_em_contato,
    count(*) FILTER (WHERE status = 'em_negociacao'::cobranca.status_caso OR status = 'acordo_ativo'::cobranca.status_caso) AS casos_em_negociacao,
    count(*) FILTER (WHERE status = 'pago'::cobranca.status_caso) AS casos_revertidos,
    count(*) FILTER (WHERE status = 'extrajudicial'::cobranca.status_caso) AS casos_extrajudicial,
    count(*) FILTER (WHERE status = 'baixado'::cobranca.status_caso) AS casos_baixados,
    round(sum(valor_total_aberto), 2) AS volume_carteira,
    round(sum(valor_revertido) FILTER (WHERE status = 'pago'::cobranca.status_caso), 2) AS volume_revertido,
    round(sum(valor_revertido) FILTER (WHERE status = 'pago'::cobranca.status_caso) / NULLIF(sum(valor_total_aberto), 0::numeric) * 100::numeric, 1) AS taxa_recuperacao_pct,
    ( SELECT count(*) AS count
           FROM cobranca.cobranca_interacoes) AS total_contatos,
    ( SELECT count(*) AS count
           FROM cobranca.cobranca_interacoes
          WHERE cobranca_interacoes.houve_retorno = true) AS total_retornos,
    ( SELECT round(count(*) FILTER (WHERE cobranca_interacoes.houve_retorno = true)::numeric / NULLIF(count(*), 0)::numeric * 100::numeric, 1) AS round
           FROM cobranca.cobranca_interacoes) AS taxa_retorno_pct,
    ( SELECT count(*) AS count
           FROM cobranca.cobranca_negociacoes
          WHERE cobranca_negociacoes.status = 'em_andamento'::cobranca.status_acordo) AS acordos_ativos,
    ( SELECT round(sum(cobranca_negociacoes.valor_total_acordado), 2) AS round
           FROM cobranca.cobranca_negociacoes
          WHERE cobranca_negociacoes.status = 'em_andamento'::cobranca.status_acordo) AS volume_em_acordo,
    ( SELECT round(sum(cobranca_negociacoes.valor_total_acordado), 2) AS round
           FROM cobranca.cobranca_negociacoes
          WHERE cobranca_negociacoes.status = 'cumprido'::cobranca.status_acordo) AS volume_acordos_cumpridos
   FROM cobranca.cobranca_casos;

CREATE OR REPLACE VIEW unipds.v_contas_a_receber AS SELECT s.nome,
    s.cpf_cnpj,
    s.email,
    s.telefone,
    c.contract_ref,
    c.voomp_contrato_id,
    c.tipo_cobranca,
    c.status_contrato,
    p.classe AS tipo_curso,
    pp.previsao_ref,
    pp.numero_parcela,
    pp.total_parcelas,
    pp.valor_previsto,
    pp.data_prevista,
    pp.status AS status_previsao,
    pp.data_pagamento AS data_confirmacao,
    pp.tenant_id,
        CASE pp.tenant_id
            WHEN '70b668e4-be85-459b-8dbb-3876929ac850'::uuid THEN 'Java'::text
            WHEN 'e717e24d-fb30-4ed0-83d3-bb8ea0b66783'::uuid THEN 'IA'::text
            ELSE NULL::text
        END AS tenant_nome
   FROM unipds.previsao_parcelas pp
     JOIN unipds.contracts c ON c.contract_id = pp.contract_id
     JOIN unipds.students s ON s.student_id = c.student_id
     JOIN unipds.v_produtos_classificados p ON p.product_id = c.product_id
  WHERE (pp.status = ANY (ARRAY['previsto'::text, 'vencido'::text, 'pago'::text])) AND c.contrato_canonico = true AND c.status_contrato <> 'Cancelado'::text AND p.classe <> 'ADMINISTRATIVO'::text AND (EXISTS ( SELECT 1
           FROM unipds.charges ch
          WHERE ch.contract_id = c.contract_id AND ch.status = 'Pago'::text AND COALESCE(ch.numero_parcela, 1) = 1))
  ORDER BY pp.tenant_id, pp.data_prevista;

CREATE OR REPLACE VIEW unipds.v_inadimplencia AS SELECT s.student_id,
    s.nome,
    s.cpf_cnpj,
    s.email,
    s.telefone,
    c.contract_ref,
    c.tipo_cobranca,
    c.status_contrato,
    p.classe AS tipo_curso,
    pp.previsao_id,
    pp.previsao_ref,
    pp.numero_parcela,
    pp.total_parcelas,
    pp.valor_previsto AS valor_devido,
    pp.data_prevista AS data_vencimento,
    CURRENT_DATE - pp.data_prevista AS dias_atraso,
        CASE
            WHEN (CURRENT_DATE - pp.data_prevista) >= 1 AND (CURRENT_DATE - pp.data_prevista) <= 30 THEN '1-30 dias'::text
            WHEN (CURRENT_DATE - pp.data_prevista) >= 31 AND (CURRENT_DATE - pp.data_prevista) <= 60 THEN '31-60 dias'::text
            WHEN (CURRENT_DATE - pp.data_prevista) >= 61 AND (CURRENT_DATE - pp.data_prevista) <= 90 THEN '61-90 dias'::text
            WHEN (CURRENT_DATE - pp.data_prevista) > 90 THEN '+90 dias'::text
            ELSE NULL::text
        END AS faixa_atraso,
    pp.tenant_id,
        CASE pp.tenant_id
            WHEN '70b668e4-be85-459b-8dbb-3876929ac850'::uuid THEN 'Java'::text
            WHEN 'e717e24d-fb30-4ed0-83d3-bb8ea0b66783'::uuid THEN 'IA'::text
            ELSE NULL::text
        END AS tenant_nome
   FROM unipds.previsao_parcelas pp
     JOIN unipds.contracts c ON c.contract_id = pp.contract_id
     JOIN unipds.students s ON s.student_id = c.student_id
     JOIN unipds.v_produtos_classificados p ON p.product_id = c.product_id
  WHERE pp.status = 'vencido'::text AND c.contrato_canonico = true AND c.status_contrato <> 'Cancelado'::text AND p.classe <> 'ADMINISTRATIVO'::text AND (EXISTS ( SELECT 1
           FROM unipds.charges ch
          WHERE ch.contract_id = c.contract_id AND ch.status = 'Pago'::text AND COALESCE(ch.numero_parcela, 1) = 1))
  ORDER BY (CURRENT_DATE - pp.data_prevista) DESC;

CREATE OR REPLACE VIEW unipds.v_matriculas_unico AS SELECT s.student_id,
    s.cpf_cnpj,
    s.nome,
    s.email,
    s.telefone,
    s.uf_origem,
    c.contract_id,
    c.contract_ref,
    c.tenant_id,
    p.classe AS tipo_curso,
    p.nome AS produto_nome,
    ch.charge_id,
    ch.valor_cobrado,
    ch.metodo_pagamento,
    ch.data_pagamento AS data_matricula,
    'UNICO'::text AS modalidade,
    NULL::integer AS parcela_atual,
    NULL::integer AS total_parcelas,
    c.status_contrato
   FROM unipds.contracts c
     JOIN unipds.students s ON s.student_id = c.student_id
     JOIN unipds.charges ch ON ch.contract_id = c.contract_id
     JOIN unipds.v_produtos_classificados p ON p.product_id = c.product_id
  WHERE c.tipo_cobranca = 'Único'::text AND ch.status = 'Pago'::text AND ch.valor_cobrado > 0::numeric AND p.classe <> 'ADMINISTRATIVO'::text AND c.contrato_canonico = true;

CREATE OR REPLACE VIEW unipds.v_matriculas_assinatura AS WITH parcelas_pagas AS (
         SELECT c.contract_id,
            c.student_id,
            c.product_id,
            c.contract_ref,
            c.voomp_contrato_id,
            c.recorrencia_total,
            c.status_contrato,
            c.tenant_id,
            min(ch.numero_parcela) AS primeira_parcela_paga,
            max(ch.numero_parcela) AS ultima_parcela_paga,
            count(ch.charge_id) AS parcelas_pagas_count,
            max(ch.data_pagamento) AS data_ultimo_pagamento,
            min(ch.data_pagamento) AS data_primeira_pagamento
           FROM unipds.contracts c
             JOIN unipds.charges ch ON ch.contract_id = c.contract_id
          WHERE c.tipo_cobranca = 'Assinatura'::text AND c.contrato_canonico = true AND ch.status = 'Pago'::text AND ch.valor_cobrado > 0::numeric
          GROUP BY c.contract_id, c.student_id, c.product_id, c.contract_ref, c.voomp_contrato_id, c.recorrencia_total, c.status_contrato, c.tenant_id
        )
 SELECT s.student_id,
    s.cpf_cnpj,
    s.nome,
    s.email,
    s.telefone,
    s.uf_origem,
    pp.contract_id,
    pp.contract_ref,
    pp.tenant_id,
    p.classe AS tipo_curso,
    p.nome AS produto_nome,
    pp.primeira_parcela_paga,
    pp.ultima_parcela_paga,
    pp.parcelas_pagas_count,
    pp.recorrencia_total AS total_parcelas_contrato,
    pp.data_primeira_pagamento AS data_matricula,
    pp.data_ultimo_pagamento,
    'ASSINATURA'::text AS modalidade,
    pp.status_contrato,
        CASE
            WHEN pp.primeira_parcela_paga > 1 THEN true
            ELSE false
        END AS anomalia_sem_p1,
        CASE
            WHEN pp.recorrencia_total = 10 THEN true
            ELSE false
        END AS anomalia_rec_10
   FROM parcelas_pagas pp
     JOIN unipds.students s ON s.student_id = pp.student_id
     JOIN unipds.v_produtos_classificados p ON p.product_id = pp.product_id
  WHERE p.classe <> 'ADMINISTRATIVO'::text;

CREATE OR REPLACE VIEW unipds.v_cruzamento_pipe AS SELECT pd.tenant_id,
    pd.ano_mes,
    pd.pipe_deal_id,
    pd.titulo,
    pd.funil,
    pd.proprietario,
    pd.pessoa_nome,
    pd.cpf_clean AS pipe_cpf_clean,
    pd.email_clean AS pipe_email_clean,
    pd.valor AS pipe_valor,
    pd.ganho_em AS pipe_ganho_em,
    cl.link_id,
    cl.criterio,
    cl.confianca,
    cl.divergencia_valor,
    cl.divergencia_classe,
    cl.cross_tenant,
    cl.contract_id,
    cl.charge_id,
    vna.contract_ref,
    vna.voomp_venda_id_primeira_parcela,
    vna.valor_recebido_total AS voomp_valor_contrato,
    vna.valor_oferta AS voomp_valor_oferta_parcela,
    vna.valor_contrato_total AS voomp_valor_contrato_bruto,
    vna.tipo_cobranca,
    vna.recorrencia_total,
    vna.valor_recebido AS voomp_valor_recebido_1a_parcela,
    vna.data_pagamento AS voomp_data_pagamento,
    vna.aluno_nome AS voomp_aluno_nome,
    vna.cpf_cnpj AS voomp_cpf,
    vna.tenant_id AS voomp_tenant_id,
        CASE
            WHEN cl.link_id IS NULL THEN 'ORFAO_PIPE'::text
            ELSE 'CASADO'::text
        END AS status_match,
        CASE
            WHEN cl.link_id IS NULL THEN 'SIM'::text
            ELSE 'NAO'::text
        END AS pendente_financeiro,
    vna.valor_cobrado_total AS voomp_valor_cobrado_total,
    vna.reembolsado AS voomp_reembolsado
   FROM unipds.pipe_deals pd
     LEFT JOIN unipds.conciliacao_links cl ON cl.tenant_id = pd.tenant_id AND cl.pipe_deal_id = pd.pipe_deal_id
     LEFT JOIN unipds.v_novos_alunos_voomp vna ON vna.contract_id = cl.contract_id
  WHERE pd.status = 'Ganho'::text;

CREATE OR REPLACE VIEW unipds.v_cruzamento_voomp AS SELECT vna.tenant_id,
    vna.ano_mes,
    vna.contract_id,
    vna.contract_ref,
    vna.voomp_contrato_id,
    vna.voomp_venda_id_primeira_parcela,
    vna.tipo_cobranca,
    vna.recorrencia_total,
    vna.aluno_nome,
    vna.cpf_cnpj,
    vna.email_clean,
    vna.fonte_nome,
    vna.produto_nome,
    vna.valor_oferta AS voomp_valor_oferta_parcela,
    vna.valor_recebido_total AS voomp_valor_contrato,
    vna.valor_contrato_total AS voomp_valor_contrato_bruto,
    vna.valor_recebido AS voomp_valor_recebido_1a_parcela,
    vna.data_pagamento,
    vna.metodo_pagamento,
    cl.link_id,
    cl.pipe_deal_id,
    cl.criterio,
    cl.confianca,
    cl.divergencia_valor,
    cl.divergencia_classe,
    cl.cross_tenant,
    cl.tenant_id AS pipe_tenant_id,
    pd.titulo AS pipe_titulo,
    pd.proprietario AS pipe_proprietario,
    pd.valor AS pipe_valor,
    pd.ganho_em AS pipe_ganho_em,
        CASE
            WHEN cl.link_id IS NULL THEN 'ORFAO_VOOMP'::text
            ELSE 'CASADO'::text
        END AS status_match,
        CASE
            WHEN cl.link_id IS NULL THEN 'SIM'::text
            ELSE 'NAO'::text
        END AS venda_orfa,
    vna.valor_cobrado_total AS voomp_valor_cobrado_total,
    vna.reembolsado AS voomp_reembolsado
   FROM unipds.v_novos_alunos_voomp vna
     LEFT JOIN unipds.conciliacao_links cl ON cl.contract_id = vna.contract_id
     LEFT JOIN unipds.pipe_deals pd ON pd.tenant_id = cl.tenant_id AND pd.pipe_deal_id = cl.pipe_deal_id;

CREATE OR REPLACE VIEW unipds.v_suspeitos_tenant_errado AS WITH orfaos_pipe AS (
         SELECT pd.tenant_id,
            pd.ano_mes,
            pd.pipe_deal_id,
            pd.pessoa_nome,
            pd.cpf_clean,
            pd.email_clean,
            pd.valor AS pipe_valor,
            pd.funil
           FROM unipds.pipe_deals pd
          WHERE pd.status = 'Ganho'::text AND NOT (EXISTS ( SELECT 1
                   FROM unipds.conciliacao_links cl
                  WHERE cl.tenant_id = pd.tenant_id AND cl.pipe_deal_id = pd.pipe_deal_id))
        ), orfaos_voomp AS (
         SELECT vna.tenant_id,
            vna.ano_mes,
            vna.contract_id,
            vna.aluno_nome,
            vna.cpf_clean,
            vna.email_clean,
            vna.valor_recebido_total AS voomp_valor
           FROM unipds.v_novos_alunos_voomp vna
          WHERE NOT (EXISTS ( SELECT 1
                   FROM unipds.conciliacao_links cl
                  WHERE cl.contract_id = vna.contract_id))
        ), nomes AS (
         SELECT op.ano_mes,
            op.tenant_id AS tenant_pipe,
            ov.tenant_id AS tenant_voomp,
            op.pipe_deal_id,
            op.funil,
            op.pessoa_nome AS pipe_nome,
            ov.aluno_nome AS voomp_nome,
            op.pipe_valor,
            ov.voomp_valor,
            op.cpf_clean AS pipe_cpf,
            ov.cpf_clean AS voomp_cpf,
            op.email_clean AS pipe_email,
            ov.email_clean AS voomp_email,
            ov.contract_id AS voomp_contract_id,
            lower(translate(regexp_replace(COALESCE(op.pessoa_nome, ''::text), '[^[:alpha:][:space:]]'::text, ''::text, 'g'::text), 'áéíóúàèìòùâêîôûãõçÁÉÍÓÚÀÈÌÒÙÂÊÎÔÛÃÕÇ'::text, 'aeiouaeiouaeiouaocaeiouaeiouaeiouaoc'::text)) AS pipe_nome_norm,
            lower(translate(regexp_replace(COALESCE(ov.aluno_nome, ''::text), '[^[:alpha:][:space:]]'::text, ''::text, 'g'::text), 'áéíóúàèìòùâêîôûãõçÁÉÍÓÚÀÈÌÒÙÂÊÎÔÛÃÕÇ'::text, 'aeiouaeiouaeiouaocaeiouaeiouaeiouaoc'::text)) AS voomp_nome_norm
           FROM orfaos_pipe op
             JOIN orfaos_voomp ov ON op.ano_mes = ov.ano_mes AND op.tenant_id <> ov.tenant_id AND (op.cpf_clean <> ''::text AND op.cpf_clean = ov.cpf_clean OR op.email_clean <> ''::text AND op.email_clean = ov.email_clean)
        )
 SELECT ano_mes,
    tenant_pipe,
    tenant_voomp,
    pipe_deal_id,
    funil,
    pipe_nome,
    voomp_nome,
    pipe_valor,
    voomp_valor,
        CASE
            WHEN pipe_cpf <> ''::text AND pipe_cpf = voomp_cpf THEN 'CPF'::text
            ELSE 'EMAIL'::text
        END AS criterio_suspeita,
    round(similarity(pipe_nome_norm, voomp_nome_norm) * 100::double precision)::integer AS similaridade_nome,
    voomp_contract_id
   FROM nomes;

CREATE OR REPLACE VIEW unipds.v_matriculas_ativas AS SELECT v_matriculas_unico.student_id,
    v_matriculas_unico.cpf_cnpj,
    v_matriculas_unico.nome,
    v_matriculas_unico.email,
    v_matriculas_unico.telefone,
    v_matriculas_unico.uf_origem,
    v_matriculas_unico.contract_id,
    v_matriculas_unico.contract_ref,
    v_matriculas_unico.tenant_id,
    v_matriculas_unico.tipo_curso,
    v_matriculas_unico.produto_nome,
    v_matriculas_unico.modalidade,
    v_matriculas_unico.data_matricula,
    v_matriculas_unico.status_contrato,
    false AS anomalia_sem_p1,
    false AS anomalia_rec_10
   FROM unipds.v_matriculas_unico
UNION ALL
 SELECT v_matriculas_assinatura.student_id,
    v_matriculas_assinatura.cpf_cnpj,
    v_matriculas_assinatura.nome,
    v_matriculas_assinatura.email,
    v_matriculas_assinatura.telefone,
    v_matriculas_assinatura.uf_origem,
    v_matriculas_assinatura.contract_id,
    v_matriculas_assinatura.contract_ref,
    v_matriculas_assinatura.tenant_id,
    v_matriculas_assinatura.tipo_curso,
    v_matriculas_assinatura.produto_nome,
    v_matriculas_assinatura.modalidade,
    v_matriculas_assinatura.data_matricula,
    v_matriculas_assinatura.status_contrato,
    v_matriculas_assinatura.anomalia_sem_p1,
    v_matriculas_assinatura.anomalia_rec_10
   FROM unipds.v_matriculas_assinatura;

CREATE OR REPLACE VIEW unipds.v_resumo_executivo AS SELECT
        CASE
            WHEN tenant_id = '70b668e4-be85-459b-8dbb-3876929ac850'::uuid THEN 'Java'::text
            WHEN tenant_id = 'e717e24d-fb30-4ed0-83d3-bb8ea0b66783'::uuid THEN 'IA'::text
            ELSE NULL::text
        END AS tenant,
    tipo_curso,
    modalidade,
    count(DISTINCT student_id) AS alunos_ativos,
    count(DISTINCT contract_id) AS contratos_ativos
   FROM unipds.v_matriculas_ativas
  GROUP BY tenant_id, tipo_curso, modalidade
  ORDER BY (
        CASE
            WHEN tenant_id = '70b668e4-be85-459b-8dbb-3876929ac850'::uuid THEN 'Java'::text
            WHEN tenant_id = 'e717e24d-fb30-4ed0-83d3-bb8ea0b66783'::uuid THEN 'IA'::text
            ELSE NULL::text
        END), tipo_curso, modalidade;
