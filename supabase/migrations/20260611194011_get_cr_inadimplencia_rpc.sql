-- ============================================================
-- RPC get_cr_inadimplencia — pacote oficial "CR + Inadimplencia + %"
--
-- Para o dashboard de Cobranca acompanhar os KPIs diariamente sem
-- reimplementar a regua nem puxar a view inteira (~30k parcelas).
--
-- Universo: carteira de ASSINATURAS, valor BRUTO (valor_oferta),
-- via faturamento.vw_parcelas_contratuais (cancelados sem boleto ja
-- excluidos; data_referencia = COALESCE(venc real, prevista)).
--
-- Colunas:
--   carteira_total          = todas as parcelas projetadas
--   realizado               = parcelas PAGAS
--   reembolsado_chargeback  = REEMBOLSADA + CHARGEBACK
--   inadimplente            = EM_ABERTO vencida (data_referencia < hoje)
--   saldo_a_realizar        = NAO_EMITIDA + EM_ABERTO no prazo
--   total_em_aberto         = inadimplente + saldo_a_realizar
--   pct_inadimplencia       = inadimplente / total_em_aberto
--     ^ REGUA OFICIAL definida pelo dono (decisao 10/06/2026):
--       sobre a carteira EM ABERTO, NAO sobre o vencido.
--
-- Retorna 1 linha por tenant + linha TOTAL CONSOLIDADO
-- (tenant_id NULL na linha total — usar tenant_id como chave).
-- SET statement_timeout 60s: a view eh live (expande cronograma);
-- protege contra o limite de 3s do role anon.
-- ============================================================

CREATE OR REPLACE FUNCTION faturamento.get_cr_inadimplencia()
RETURNS TABLE(
    tenant                 text,
    tenant_id              uuid,
    carteira_total         numeric,
    realizado              numeric,
    reembolsado_chargeback numeric,
    inadimplente           numeric,
    saldo_a_realizar       numeric,
    total_em_aberto        numeric,
    pct_inadimplencia      numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'faturamento','unipds','public'
SET statement_timeout TO '60s'
AS $$
WITH base AS (
  SELECT t.nome AS tenant, t.tenant_id, vpc.status_parcela, vpc.data_referencia, vpc.valor_previsto
  FROM faturamento.vw_parcelas_contratuais vpc
  JOIN unipds.tenants t ON t.tenant_id = vpc.tenant_id
),
agg AS (
  SELECT
    COALESCE(b.tenant, 'TOTAL CONSOLIDADO') AS tenant,
    CASE WHEN b.tenant IS NULL THEN NULL ELSE MAX(b.tenant_id::text)::uuid END AS tenant_id,
    SUM(b.valor_previsto) AS carteira_total,
    SUM(CASE WHEN b.status_parcela='PAGA' THEN b.valor_previsto ELSE 0 END) AS realizado,
    SUM(CASE WHEN b.status_parcela IN ('REEMBOLSADA','CHARGEBACK') THEN b.valor_previsto ELSE 0 END) AS reembolsado_chargeback,
    SUM(CASE WHEN b.status_parcela='EM_ABERTO' AND b.data_referencia < CURRENT_DATE THEN b.valor_previsto ELSE 0 END) AS inadimplente,
    SUM(CASE WHEN b.status_parcela='NAO_EMITIDA'
              OR (b.status_parcela='EM_ABERTO' AND b.data_referencia >= CURRENT_DATE)
             THEN b.valor_previsto ELSE 0 END) AS saldo_a_realizar
  FROM base b
  GROUP BY ROLLUP(b.tenant)
)
SELECT
  a.tenant,
  a.tenant_id,
  a.carteira_total,
  a.realizado,
  a.reembolsado_chargeback,
  a.inadimplente,
  a.saldo_a_realizar,
  (a.inadimplente + a.saldo_a_realizar)                                        AS total_em_aberto,
  ROUND(100.0 * a.inadimplente / NULLIF(a.inadimplente + a.saldo_a_realizar,0), 2) AS pct_inadimplencia
FROM agg a
ORDER BY (a.tenant = 'TOTAL CONSOLIDADO') DESC, a.tenant;
$$;

COMMENT ON FUNCTION faturamento.get_cr_inadimplencia() IS
  'Pacote oficial CR + Inadimplencia + %. pct_inadimplencia = inadimplente/(inadimplente+saldo_a_realizar) — regua sobre carteira em aberto (decisao do dono, 10/06/2026). 1 linha por tenant + TOTAL CONSOLIDADO (tenant_id NULL).';

GRANT EXECUTE ON FUNCTION faturamento.get_cr_inadimplencia()
    TO anon, authenticated, service_role;

-- Wrapper em public para supabase.rpc() simples
CREATE OR REPLACE FUNCTION public.get_cr_inadimplencia()
RETURNS TABLE(
    tenant                 text,
    tenant_id              uuid,
    carteira_total         numeric,
    realizado              numeric,
    reembolsado_chargeback numeric,
    inadimplente           numeric,
    saldo_a_realizar       numeric,
    total_em_aberto        numeric,
    pct_inadimplencia      numeric
)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT * FROM faturamento.get_cr_inadimplencia();
$$;

GRANT EXECUTE ON FUNCTION public.get_cr_inadimplencia()
    TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
