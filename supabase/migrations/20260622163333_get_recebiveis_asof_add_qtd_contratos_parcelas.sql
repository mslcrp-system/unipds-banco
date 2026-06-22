-- ============================================================
-- get_recebiveis_asof: + quantidade de contratos e parcelas
--
-- Adiciona qtd_contratos (distintos), qtd_parcelas (total), qtd_vencido
-- e qtd_a_vencer (parcelas em cada balde). DROP+CREATE porque muda o
-- retorno. Restante da logica identico (regua faturamento_total, as-of,
-- vencido alinhado a CR).
-- ============================================================

DROP FUNCTION IF EXISTS fechamento.get_recebiveis_asof(date);

CREATE OR REPLACE FUNCTION fechamento.get_recebiveis_asof(p_data date DEFAULT CURRENT_DATE)
 RETURNS TABLE(tenant text, tenant_id uuid, carteira_total numeric, realizado numeric,
               reembolso_cb numeric, vencido numeric, a_vencer numeric,
               total_a_receber numeric, pct_vencido numeric,
               qtd_contratos bigint, qtd_parcelas bigint,
               qtd_vencido bigint, qtd_a_vencer bigint)
 LANGUAGE sql STABLE SECURITY DEFINER
 SET search_path TO 'fechamento', 'unipds', 'public'
 SET statement_timeout TO '60s'
AS $function$
WITH base AS (
    SELECT t.nome AS tenant, r.tenant_id, r.contract_id, r.valor, r.data_referencia,
           r.data_pagamento, r.status_parcela
    FROM fechamento.vw_recebiveis_parcela r
    JOIN unipds.tenants t ON t.tenant_id = r.tenant_id
),
agg AS (
    SELECT
        COALESCE(b.tenant, 'TOTAL CONSOLIDADO') AS tenant,
        CASE WHEN b.tenant IS NULL THEN NULL ELSE max(b.tenant_id::text)::uuid END AS tenant_id,
        SUM(b.valor) AS carteira_total,
        SUM(b.valor) FILTER (WHERE b.data_pagamento IS NOT NULL AND b.data_pagamento <= p_data) AS realizado,
        SUM(b.valor) FILTER (WHERE b.status_parcela IN ('REEMBOLSADA','CHARGEBACK')) AS reembolso_cb,
        SUM(b.valor) FILTER (WHERE (b.data_pagamento IS NULL OR b.data_pagamento > p_data)
                              AND b.status_parcela = 'EM_ABERTO'
                              AND b.data_referencia <  p_data) AS vencido,
        SUM(b.valor) FILTER (WHERE (b.data_pagamento IS NULL OR b.data_pagamento > p_data)
                              AND b.status_parcela NOT IN ('REEMBOLSADA','CHARGEBACK')
                              AND NOT (b.status_parcela = 'EM_ABERTO' AND b.data_referencia < p_data)) AS a_vencer,
        count(DISTINCT b.contract_id) AS qtd_contratos,
        count(*)                      AS qtd_parcelas,
        count(*) FILTER (WHERE (b.data_pagamento IS NULL OR b.data_pagamento > p_data)
                          AND b.status_parcela = 'EM_ABERTO'
                          AND b.data_referencia <  p_data) AS qtd_vencido,
        count(*) FILTER (WHERE (b.data_pagamento IS NULL OR b.data_pagamento > p_data)
                          AND b.status_parcela NOT IN ('REEMBOLSADA','CHARGEBACK')
                          AND NOT (b.status_parcela = 'EM_ABERTO' AND b.data_referencia < p_data)) AS qtd_a_vencer
    FROM base b
    GROUP BY ROLLUP(b.tenant)
)
SELECT a.tenant, a.tenant_id, a.carteira_total,
       COALESCE(a.realizado,0), COALESCE(a.reembolso_cb,0),
       COALESCE(a.vencido,0), COALESCE(a.a_vencer,0),
       (COALESCE(a.vencido,0)+COALESCE(a.a_vencer,0)),
       ROUND(100.0*COALESCE(a.vencido,0)/NULLIF(COALESCE(a.vencido,0)+COALESCE(a.a_vencer,0),0),2),
       a.qtd_contratos, a.qtd_parcelas, a.qtd_vencido, a.qtd_a_vencer
FROM agg a
ORDER BY (a.tenant='TOTAL CONSOLIDADO') DESC, a.tenant;
$function$;

GRANT EXECUTE ON FUNCTION fechamento.get_recebiveis_asof(date) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
