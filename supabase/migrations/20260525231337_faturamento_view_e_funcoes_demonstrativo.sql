-- ============================================================
-- Schema faturamento: view base + 3 funcoes de demonstrativo
--
-- Regras aplicadas:
--   1. Apenas ASSINATURA (vendas unicas ficam fora — D3)
--   2. Escala BRUTA (valor_oferta do contrato) em todas as colunas — D1
--   3. Contratos Cancelados: parcelas NAO_EMITIDA sao removidas (D2);
--      parcelas com boleto ja emitido (PAGA, EM_ABERTO, REEMBOLSADA,
--      CHARGEBACK) continuam contando (faturamento ja realizado)
--   4. Data de referencia mensal: COALESCE(data_vencimento_real,
--      data_prevista) — verdade Voomp quando boleto foi emitido
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- View base: vw_parcelas_contratuais
-- Expande as N parcelas teoricas de cada contrato ativo de
-- assinatura, cruza com charges/refunds reais e aplica os
-- filtros das decisoes acima.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW faturamento.vw_parcelas_contratuais AS
WITH p1_paga AS (
    SELECT
        c.contract_id,
        c.data_vencimento AS vencimento_p1
    FROM unipds.charges c
    WHERE c.tipo_cobranca = 'Assinatura'
      AND c.numero_parcela = 1
      AND c.categoria = 'PAGO'
      AND c.contract_id IS NOT NULL
),
contratos_base AS (
    SELECT
        ct.contract_id,
        ct.tenant_id,
        ct.student_id,
        ct.product_id,
        ct.voomp_contrato_id,
        ct.recorrencia_total,
        ct.valor_oferta,
        ct.status_contrato,
        ct.periodo,
        ct.data_primeira_venda,
        p1.vencimento_p1
    FROM unipds.contracts ct
    JOIN p1_paga p1 ON p1.contract_id = ct.contract_id
    WHERE ct.recorrencia_total IS NOT NULL
      AND ct.recorrencia_total > 0
      AND ct.tipo_cobranca = 'Assinatura'
),
parcelas_expansao AS (
    SELECT
        cb.*,
        n AS numero_parcela,
        CASE COALESCE(cb.periodo, 'Mensal')
            WHEN 'Mensal'      THEN cb.vencimento_p1 + ((n - 1) * INTERVAL '1 month')
            WHEN 'Semestral'   THEN cb.vencimento_p1 + ((n - 1) * INTERVAL '6 months')
            WHEN 'Anual'       THEN cb.vencimento_p1 + ((n - 1) * INTERVAL '1 year')
            WHEN 'Trimestral'  THEN cb.vencimento_p1 + ((n - 1) * INTERVAL '3 months')
            ELSE                    cb.vencimento_p1 + ((n - 1) * INTERVAL '1 month')
        END::date AS data_prevista
    FROM contratos_base cb
    CROSS JOIN LATERAL generate_series(1, cb.recorrencia_total) AS n
),
com_charge AS (
    SELECT
        pe.*,
        ch.charge_id,
        ch.categoria       AS categoria_charge,
        ch.data_vencimento AS data_vencimento_real,
        ch.data_pagamento,
        ch.valor_cobrado
    FROM parcelas_expansao pe
    LEFT JOIN unipds.charges ch
        ON ch.contract_id    = pe.contract_id
       AND ch.numero_parcela = pe.numero_parcela
),
com_refund AS (
    SELECT
        cc.*,
        r.tipo AS tipo_refund
    FROM com_charge cc
    LEFT JOIN unipds.refunds r ON r.charge_id = cc.charge_id
)
SELECT
    cr.contract_id,
    cr.tenant_id,
    cr.student_id,
    cr.product_id,
    cr.voomp_contrato_id,
    cr.status_contrato,
    cr.recorrencia_total,
    cr.valor_oferta                       AS valor_previsto,    -- escala BRUTA
    cr.data_primeira_venda,
    cr.numero_parcela,
    cr.data_prevista,
    cr.data_vencimento_real,
    cr.data_pagamento,
    -- Mes de referencia: real quando emitiu, teorica quando nao
    COALESCE(cr.data_vencimento_real, cr.data_prevista)::date AS data_referencia,
    CASE
        WHEN cr.tipo_refund = 'Reembolso'      THEN 'REEMBOLSADA'
        WHEN cr.tipo_refund = 'Chargeback'     THEN 'CHARGEBACK'
        WHEN cr.categoria_charge = 'PAGO'      THEN 'PAGA'
        WHEN cr.categoria_charge = 'ABERTO'    THEN 'EM_ABERTO'
        WHEN cr.categoria_charge IS NULL       THEN 'NAO_EMITIDA'
        ELSE 'INDEFINIDA'
    END AS status_parcela,
    cr.charge_id
FROM com_refund cr
-- D2: contrato Cancelado perde parcelas NAO_EMITIDA. Parcelas ja
--     emitidas (PAGA/EM_ABERTO/REEMBOLSADA/CHARGEBACK) continuam.
WHERE NOT (cr.status_contrato = 'Cancelado' AND cr.categoria_charge IS NULL);

COMMENT ON VIEW faturamento.vw_parcelas_contratuais IS
  'Base do demonstrativo de faturamento: expande N parcelas de contratos de Assinatura, escala bruta (valor_oferta), filtra cancelados sem boleto, mes referencia respeita data_vencimento_real.';

GRANT SELECT ON faturamento.vw_parcelas_contratuais TO anon, authenticated, service_role;


-- ────────────────────────────────────────────────────────────
-- 1) get_faturamento_mensal
--    Curva total mensal: esperado, realizado, inadimplente,
--    reembolsado, saldo_aberto. Tudo em valor bruto contratual.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION faturamento.get_faturamento_mensal(p_tenant_id uuid DEFAULT NULL)
RETURNS TABLE(
    mes           text,
    status_mes    text,
    esperado      numeric,
    realizado     numeric,
    inadimplente  numeric,
    reembolsado   numeric,
    saldo_aberto  numeric
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'faturamento','unipds','public'
AS $$
    WITH base AS (
        SELECT
            to_char(data_referencia, 'YYYY-MM') AS mes,
            data_referencia,
            valor_previsto,
            status_parcela
        FROM faturamento.vw_parcelas_contratuais
        WHERE p_tenant_id IS NULL OR tenant_id = p_tenant_id
    )
    SELECT
        mes,
        CASE
            WHEN mes <  to_char(date_trunc('month', CURRENT_DATE), 'YYYY-MM') THEN 'passado'
            WHEN mes =  to_char(date_trunc('month', CURRENT_DATE), 'YYYY-MM') THEN 'corrente'
            ELSE 'futuro'
        END AS status_mes,
        SUM(valor_previsto)                                                  AS esperado,
        SUM(CASE WHEN status_parcela = 'PAGA'
                 THEN valor_previsto ELSE 0 END)                              AS realizado,
        -- Inadimplente: emitida pela Voomp + venceu + ainda nao paga
        SUM(CASE WHEN status_parcela = 'EM_ABERTO'
                  AND data_referencia < CURRENT_DATE
                 THEN valor_previsto ELSE 0 END)                              AS inadimplente,
        SUM(CASE WHEN status_parcela IN ('REEMBOLSADA','CHARGEBACK')
                 THEN valor_previsto ELSE 0 END)                              AS reembolsado,
        -- Saldo aberto: futuro + emitido mas ainda no prazo + nao emitida
        SUM(CASE WHEN status_parcela = 'NAO_EMITIDA'
                   OR (status_parcela = 'EM_ABERTO' AND data_referencia >= CURRENT_DATE)
                 THEN valor_previsto ELSE 0 END)                              AS saldo_aberto
    FROM base
    GROUP BY mes
    ORDER BY mes;
$$;

COMMENT ON FUNCTION faturamento.get_faturamento_mensal(uuid) IS
  'Curva mensal consolidada do faturamento de assinatura. Escala bruta. Inadimplencia respeita data real do boleto Voomp.';

GRANT EXECUTE ON FUNCTION faturamento.get_faturamento_mensal(uuid)
    TO anon, authenticated, service_role;


-- ────────────────────────────────────────────────────────────
-- 2) get_faturamento_por_tenant
--    Igual a get_faturamento_mensal, quebrado por tenant.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION faturamento.get_faturamento_por_tenant(p_tenant_id uuid DEFAULT NULL)
RETURNS TABLE(
    mes           text,
    tenant_id     uuid,
    tenant_nome   text,
    status_mes    text,
    esperado      numeric,
    realizado     numeric,
    inadimplente  numeric,
    reembolsado   numeric,
    saldo_aberto  numeric
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'faturamento','unipds','public'
AS $$
    WITH base AS (
        SELECT
            to_char(vpc.data_referencia, 'YYYY-MM') AS mes,
            vpc.data_referencia,
            vpc.tenant_id,
            t.nome AS tenant_nome,
            vpc.valor_previsto,
            vpc.status_parcela
        FROM faturamento.vw_parcelas_contratuais vpc
        JOIN unipds.tenants t ON t.tenant_id = vpc.tenant_id
        WHERE p_tenant_id IS NULL OR vpc.tenant_id = p_tenant_id
    )
    SELECT
        mes,
        tenant_id,
        tenant_nome,
        CASE
            WHEN mes <  to_char(date_trunc('month', CURRENT_DATE), 'YYYY-MM') THEN 'passado'
            WHEN mes =  to_char(date_trunc('month', CURRENT_DATE), 'YYYY-MM') THEN 'corrente'
            ELSE 'futuro'
        END AS status_mes,
        SUM(valor_previsto)                                                  AS esperado,
        SUM(CASE WHEN status_parcela = 'PAGA'
                 THEN valor_previsto ELSE 0 END)                              AS realizado,
        SUM(CASE WHEN status_parcela = 'EM_ABERTO'
                  AND data_referencia < CURRENT_DATE
                 THEN valor_previsto ELSE 0 END)                              AS inadimplente,
        SUM(CASE WHEN status_parcela IN ('REEMBOLSADA','CHARGEBACK')
                 THEN valor_previsto ELSE 0 END)                              AS reembolsado,
        SUM(CASE WHEN status_parcela = 'NAO_EMITIDA'
                   OR (status_parcela = 'EM_ABERTO' AND data_referencia >= CURRENT_DATE)
                 THEN valor_previsto ELSE 0 END)                              AS saldo_aberto
    FROM base
    GROUP BY mes, tenant_id, tenant_nome
    ORDER BY mes, tenant_nome;
$$;

COMMENT ON FUNCTION faturamento.get_faturamento_por_tenant(uuid) IS
  'Curva mensal de faturamento de assinatura quebrada por tenant.';

GRANT EXECUTE ON FUNCTION faturamento.get_faturamento_por_tenant(uuid)
    TO anon, authenticated, service_role;


-- ────────────────────────────────────────────────────────────
-- 3) get_cohort_faturamento
--    Cohort: mes de entrada (data_primeira_venda) x mes recebido.
--    Soma valor BRUTO previsto das parcelas efetivamente PAGAS.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION faturamento.get_cohort_faturamento(p_tenant_id uuid DEFAULT NULL)
RETURNS TABLE(
    mes_entrada   text,
    mes_recebido  text,
    receita       numeric,
    contratos     bigint
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'faturamento','unipds','public'
AS $$
    SELECT
        to_char(data_primeira_venda, 'YYYY-MM') AS mes_entrada,
        to_char(data_pagamento,      'YYYY-MM') AS mes_recebido,
        SUM(valor_previsto)                     AS receita,
        COUNT(DISTINCT contract_id)             AS contratos
    FROM faturamento.vw_parcelas_contratuais
    WHERE status_parcela = 'PAGA'
      AND data_pagamento IS NOT NULL
      AND data_primeira_venda IS NOT NULL
      AND (p_tenant_id IS NULL OR tenant_id = p_tenant_id)
    GROUP BY 1, 2
    ORDER BY 1, 2;
$$;

COMMENT ON FUNCTION faturamento.get_cohort_faturamento(uuid) IS
  'Cohort de receita: cruza mes de entrada do contrato (data_primeira_venda) com mes em que cada parcela foi efetivamente paga. Escala bruta.';

GRANT EXECUTE ON FUNCTION faturamento.get_cohort_faturamento(uuid)
    TO anon, authenticated, service_role;
