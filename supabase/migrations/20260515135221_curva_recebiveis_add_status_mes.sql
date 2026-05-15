DROP FUNCTION IF EXISTS public.get_curva_recebiveis_mensal(uuid);

CREATE FUNCTION public.get_curva_recebiveis_mensal(p_tenant_id uuid DEFAULT NULL)
RETURNS TABLE(
  mes text,
  tenant_nome text,
  status_mes text,
  esperado numeric,
  realizado numeric,
  inadimplente numeric,
  cancelado numeric,
  saldo_aberto numeric
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'unipds', 'public'
AS $function$
  WITH base AS (
    SELECT
      pp.tenant_id,
      CASE pp.tenant_id
        WHEN '70b668e4-be85-459b-8dbb-3876929ac850'::uuid THEN 'Java'
        WHEN 'e717e24d-fb30-4ed0-83d3-bb8ea0b66783'::uuid THEN 'IA'
      END AS tenant_nome,
      TO_CHAR(pp.data_prevista, 'YYYY-MM')   AS mes_previsto,
      TO_CHAR(pp.data_pagamento, 'YYYY-MM')  AS mes_pago,
      pp.status,
      pp.valor_previsto
    FROM unipds.previsao_parcelas pp
    JOIN unipds.contracts co ON co.contract_id = pp.contract_id
    WHERE co.contrato_canonico = true
      AND co.tipo_cobranca     = 'Assinatura'
      AND (p_tenant_id IS NULL OR pp.tenant_id = p_tenant_id)
  ),
  esperado_mes AS (
    SELECT mes_previsto AS mes, tenant_nome,
           ROUND(SUM(valor_previsto)::numeric, 2) AS esperado
    FROM base
    WHERE status IN ('previsto','vencido','pago','cancelado')
    GROUP BY mes_previsto, tenant_nome
  ),
  realizado_mes AS (
    SELECT mes_pago AS mes, tenant_nome,
           ROUND(SUM(valor_previsto)::numeric, 2) AS realizado
    FROM base
    WHERE status = 'pago' AND mes_pago IS NOT NULL
    GROUP BY mes_pago, tenant_nome
  ),
  inadimplente_mes AS (
    SELECT mes_previsto AS mes, tenant_nome,
           ROUND(SUM(valor_previsto)::numeric, 2) AS inadimplente
    FROM base
    WHERE status = 'vencido'
    GROUP BY mes_previsto, tenant_nome
  ),
  cancelado_mes AS (
    SELECT mes_previsto AS mes, tenant_nome,
           ROUND(SUM(valor_previsto)::numeric, 2) AS cancelado
    FROM base
    WHERE status = 'cancelado'
    GROUP BY mes_previsto, tenant_nome
  ),
  mes_atual AS (
    SELECT TO_CHAR(CURRENT_DATE, 'YYYY-MM') AS m
  )
  SELECT
    e.mes,
    e.tenant_nome,
    CASE
      WHEN e.mes < (SELECT m FROM mes_atual) THEN 'passado'
      WHEN e.mes = (SELECT m FROM mes_atual) THEN 'corrente'
      ELSE 'futuro'
    END AS status_mes,
    e.esperado,
    COALESCE(r.realizado, 0)        AS realizado,
    COALESCE(i.inadimplente, 0)     AS inadimplente,
    COALESCE(c.cancelado, 0)        AS cancelado,
    ROUND((e.esperado
           - COALESCE(r.realizado, 0)
           - COALESCE(c.cancelado, 0))::numeric, 2) AS saldo_aberto
  FROM esperado_mes e
  LEFT JOIN realizado_mes    r ON r.mes = e.mes AND r.tenant_nome = e.tenant_nome
  LEFT JOIN inadimplente_mes i ON i.mes = e.mes AND i.tenant_nome = e.tenant_nome
  LEFT JOIN cancelado_mes    c ON c.mes = e.mes AND c.tenant_nome = e.tenant_nome
  WHERE e.mes IS NOT NULL
  ORDER BY e.mes, e.tenant_nome;
$function$;

COMMENT ON FUNCTION public.get_curva_recebiveis_mensal(uuid) IS
  'Curva de runway de recebiveis: esperado vs realizado mes a mes, com decomposicao em inadimplente e cancelado. Coluna status_mes classifica cada linha como passado/corrente/futuro (UTC). Base: previsao_parcelas. Apenas assinaturas canonicas.';
