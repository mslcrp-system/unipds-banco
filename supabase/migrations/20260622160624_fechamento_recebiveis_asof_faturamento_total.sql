-- ============================================================
-- Recebiveis do fechamento na regua faturamento_total + as-of date.
--
-- O fechamento usa: total a receber = VENCIDO + A VENCER (somatoria).
-- Como e soma, o numero independe da definicao de inadimplencia (a
-- parcela teorica nao-emitida esta no total de qualquer forma). O que
-- muda o valor e (1) a regua e (2) a data — resolvidos aqui.
--
-- REGUA: cada parcela vale o faturamento_total da P1 do contrato (mesma
-- unidade do TCV gerencial). Necessario porque a charge de parcela
-- EM_ABERTO tem faturamento_total=0 (nada pago) — pro "a receber" usamos
-- o valor real da entrada.
--
-- AS-OF: realizado = pago ate p_data; a receber = o resto (nao pago ate
-- p_data); vencido se o vencimento (data_referencia) ja passou na p_data.
--
-- Assinatura-only (a vista nao tem recebivel futuro). REEMBOLSADA/
-- CHARGEBACK ficam fora do a-receber (reversados).
--
-- SPLIT alinhado a CR: vencido = EM_ABERTO emitida vencida (mesma regua
-- da inadimplencia oficial, so em faturamento_total); a_vencer = todo o
-- resto a receber (NAO_EMITIDA + EM_ABERTO futura). total_a_receber =
-- vencido + a_vencer e INVARIANTE a essa escolha (a somatoria do dono).
-- ============================================================

CREATE OR REPLACE VIEW fechamento.vw_recebiveis_parcela AS
WITH p1 AS (
    SELECT contract_id, max(faturamento_total) AS ft_unit
    FROM unipds.charges
    WHERE tipo_cobranca = 'Assinatura' AND numero_parcela = 1
      AND data_pagamento IS NOT NULL
    GROUP BY contract_id
)
SELECT vpc.tenant_id,
       vpc.contract_id,
       vpc.product_id,
       pc.classe,
       pc.categoria,
       vpc.numero_parcela,
       vpc.data_referencia,
       vpc.data_pagamento,
       vpc.status_parcela,
       p1.ft_unit AS valor
FROM faturamento.vw_parcelas_contratuais vpc
JOIN p1                                  ON p1.contract_id = vpc.contract_id
JOIN unipds.v_produtos_classificados pc  ON pc.product_id  = vpc.product_id;

GRANT SELECT ON fechamento.vw_recebiveis_parcela TO anon, authenticated, service_role;

-- ------------------------------------------------------------
-- RPC as-of: total a receber (vencido + a vencer) em faturamento_total
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fechamento.get_recebiveis_asof(p_data date DEFAULT CURRENT_DATE)
 RETURNS TABLE(tenant text, tenant_id uuid, carteira_total numeric, realizado numeric,
               reembolso_cb numeric, vencido numeric, a_vencer numeric,
               total_a_receber numeric, pct_vencido numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'fechamento', 'unipds', 'public'
 SET statement_timeout TO '60s'
AS $function$
WITH base AS (
    SELECT t.nome AS tenant, r.tenant_id, r.valor, r.data_referencia,
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
        SUM(b.valor) FILTER (WHERE b.status_parcela IN ('REEMBOLSADA','CHARGEBACK'))             AS reembolso_cb,
        -- vencido = inadimplencia oficial (EM_ABERTO emitida e vencida)
        SUM(b.valor) FILTER (WHERE (b.data_pagamento IS NULL OR b.data_pagamento > p_data)
                              AND b.status_parcela = 'EM_ABERTO'
                              AND b.data_referencia <  p_data) AS vencido,
        -- a_vencer = todo o resto a receber (NAO_EMITIDA + EM_ABERTO futura)
        SUM(b.valor) FILTER (WHERE (b.data_pagamento IS NULL OR b.data_pagamento > p_data)
                              AND b.status_parcela NOT IN ('REEMBOLSADA','CHARGEBACK')
                              AND NOT (b.status_parcela = 'EM_ABERTO' AND b.data_referencia < p_data)) AS a_vencer
    FROM base b
    GROUP BY ROLLUP(b.tenant)
)
SELECT a.tenant, a.tenant_id,
       a.carteira_total,
       COALESCE(a.realizado,0)   AS realizado,
       COALESCE(a.reembolso_cb,0) AS reembolso_cb,
       COALESCE(a.vencido,0)     AS vencido,
       COALESCE(a.a_vencer,0)    AS a_vencer,
       (COALESCE(a.vencido,0) + COALESCE(a.a_vencer,0)) AS total_a_receber,
       ROUND(100.0 * COALESCE(a.vencido,0) / NULLIF(COALESCE(a.vencido,0)+COALESCE(a.a_vencer,0),0), 2) AS pct_vencido
FROM agg a
ORDER BY (a.tenant = 'TOTAL CONSOLIDADO') DESC, a.tenant;
$function$;

GRANT EXECUTE ON FUNCTION fechamento.get_recebiveis_asof(date) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
