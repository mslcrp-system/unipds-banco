-- ============================================================
-- Reset cirurgico do ETL Voomp
--
-- Apaga TUDO que era operacional do ETL antigo, preservando:
--   - raw_imports / raw_lines (fonte da verdade, 88.357 linhas)
--   - raw_lines_skipped (inbox novo, vazio)
--   - tenants / fontes (configuracao)
--   - classificar_raw_line (funcao do ETL novo, ja aplicada)
--   - schema financeiro intacto (excecao: 2 views que dependiam de contract_ref)
--
-- Apoś este reset, ETL novo grava direto no schema final, sem
-- conviver com lixo do passado.
-- ============================================================

-- ETAPA 1: DROP de views herdadas (todas)
DROP VIEW IF EXISTS unipds.v_inadimplencia CASCADE;
DROP VIEW IF EXISTS unipds.v_contas_a_receber CASCADE;
DROP VIEW IF EXISTS unipds.v_cobracas_reais CASCADE;
DROP VIEW IF EXISTS unipds.v_matriculas_ativas CASCADE;
DROP VIEW IF EXISTS unipds.v_matriculas_assinatura CASCADE;
DROP VIEW IF EXISTS unipds.v_matriculas_unico CASCADE;
DROP VIEW IF EXISTS unipds.v_novos_alunos_voomp CASCADE;
DROP VIEW IF EXISTS unipds.v_evasao CASCADE;
DROP VIEW IF EXISTS unipds.v_cruzamento_pipe CASCADE;
DROP VIEW IF EXISTS unipds.v_cruzamento_voomp CASCADE;
DROP VIEW IF EXISTS unipds.v_resumo_executivo CASCADE;
DROP VIEW IF EXISTS cobranca.v_casos_completos CASCADE;
DROP VIEW IF EXISTS financeiro.v_cruzamento_omie_voomp CASCADE;
DROP VIEW IF EXISTS financeiro.v_auditoria_voomp CASCADE;

-- ETAPA 2: DROP de funcoes herdadas
DROP FUNCTION IF EXISTS unipds.gerar_previsoes_pendentes() CASCADE;
DROP FUNCTION IF EXISTS unipds.gerar_previsao_parcelas(uuid) CASCADE;
DROP FUNCTION IF EXISTS unipds.gerar_contract_ref(uuid, text, text) CASCADE;
DROP FUNCTION IF EXISTS unipds.atualizar_dias_atraso() CASCADE;
DROP FUNCTION IF EXISTS unipds.recalcular_previsao_vencida() CASCADE;
DROP FUNCTION IF EXISTS unipds.executar_cruzamento(uuid, text) CASCADE;
DROP FUNCTION IF EXISTS unipds.tg_validar_ingestao_antes_fechamento() CASCADE;
DROP FUNCTION IF EXISTS unipds.get_parcelas_vencidas() CASCADE;
DROP FUNCTION IF EXISTS public.get_parcelas_vencidas() CASCADE;
DROP FUNCTION IF EXISTS cobranca.gerar_casos_inadimplencia() CASCADE;
DROP FUNCTION IF EXISTS public.get_recebiveis_mensal(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.get_cohort_recebiveis(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.get_curva_recebiveis_mensal(uuid) CASCADE;

-- ETAPA 3: DROP de jobs pg_cron herdados (4 jobs)
SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname IN (
  'unipds_recalcular_vencida_1',
  'unipds_gerar_previsoes',
  'unipds_recalcular_vencida_2',
  'unipds_gerar_casos'
);

-- ETAPA 4: DROP de tabelas operacionais erradas (preservar dados via CASCADE)
DROP TABLE IF EXISTS cobranca.cobranca_interacoes CASCADE;
DROP TABLE IF EXISTS cobranca.cobranca_negociacoes CASCADE;
DROP TABLE IF EXISTS cobranca.cobranca_casos CASCADE;
DROP TABLE IF EXISTS cobranca.casos_anomalia CASCADE;
DROP TABLE IF EXISTS unipds.previsao_parcelas CASCADE;
DROP TABLE IF EXISTS unipds.fechamentos_mensais CASCADE;
DROP TABLE IF EXISTS unipds.conciliacao_links CASCADE;
DROP TABLE IF EXISTS unipds.conciliacao_runs CASCADE;
DROP TABLE IF EXISTS unipds.ingestao_status CASCADE;
DROP TABLE IF EXISTS unipds.pipe_deals CASCADE;

-- ETAPA 5: DROP das colunas redundantes em contracts
ALTER TABLE unipds.contracts
  DROP COLUMN IF EXISTS contract_ref CASCADE,
  DROP COLUMN IF EXISTS contrato_canonico CASCADE,
  DROP COLUMN IF EXISTS contrato_espelho_de CASCADE;

-- ETAPA 6: TRUNCATE das tabelas fato (sera repopulado pelo ETL)
TRUNCATE TABLE unipds.refunds CASCADE;
TRUNCATE TABLE unipds.payment_attempts CASCADE;
TRUNCATE TABLE unipds.charges CASCADE;
TRUNCATE TABLE unipds.contracts CASCADE;
TRUNCATE TABLE unipds.products CASCADE;
TRUNCATE TABLE unipds.students CASCADE;

-- ETAPA 7: DROP da funcao upsert_students_from_raw e upsert_products_from_raw
-- (vamos reescreve-las sem amarras a contrato_canonico/contract_ref)
DROP FUNCTION IF EXISTS unipds.upsert_students_from_raw(text) CASCADE;
DROP FUNCTION IF EXISTS unipds.upsert_products_from_raw(text) CASCADE;

-- Schema preservado:
--   ✓ unipds.tenants (2)
--   ✓ unipds.fontes (2)
--   ✓ unipds.raw_imports (12)
--   ✓ unipds.raw_lines (88.357)
--   ✓ unipds.raw_lines_skipped (0)
--   ✓ unipds.students (truncated, schema preserved)
--   ✓ unipds.products (truncated, schema preserved)
--   ✓ unipds.contracts (truncated + 3 colunas dropadas)
--   ✓ unipds.charges (truncated, schema com tenant_id/student_id/product_id já preservado)
--   ✓ unipds.payment_attempts (truncated)
--   ✓ unipds.refunds (truncated)
--   ✓ unipds.classificar_raw_line (intocado)
--   ✓ schema financeiro (apenas 2 views dropadas)
--   ✓ schema cobranca (tabelas dropadas, schema vazio aguardando uso futuro)
