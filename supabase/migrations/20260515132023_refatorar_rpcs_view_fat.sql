-- ============================================================
-- PARTE 1: Remover funções antigas substituídas ou descartadas
-- ============================================================

DROP FUNCTION IF EXISTS public.get_faturamento_mensal(uuid);
DROP FUNCTION IF EXISTS public.get_cohort_assinaturas(uuid);
DROP FUNCTION IF EXISTS public.get_curva_assinaturas(uuid);

-- ============================================================
-- PARTE 2: get_recebiveis_mensal (substitui get_faturamento_mensal)
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_recebiveis_mensal(p_tenant_id uuid DEFAULT NULL)
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
$function$;

COMMENT ON FUNCTION public.get_recebiveis_mensal(uuid) IS
  'Recebiveis liquidos mensais (valor_recebido) agrupados por mes de pagamento e tipo de cobranca. Para faturamento bruto (DRE) usar funcao separada quando criada.';

-- ============================================================
-- PARTE 3: get_cohort_recebiveis (substitui get_cohort_assinaturas)
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_cohort_recebiveis(p_tenant_id uuid DEFAULT NULL)
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
    TO_CHAR(ch.data_pagamento, 'YYYY-MM') AS mes_recebido,
    (
      (DATE_PART('year',  ch.data_pagamento) - DATE_PART('year',  (pp.mes_entrada || '-01')::date)) * 12
      + DATE_PART('month', ch.data_pagamento) - DATE_PART('month', (pp.mes_entrada || '-01')::date)
    )::integer AS mes_offset,
    COUNT(DISTINCT ch.contract_id) AS contratos,
    ROUND(SUM(ch.valor_recebido)::numeric, 2) AS receita
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
$function$;

COMMENT ON FUNCTION public.get_cohort_recebiveis(uuid) IS
  'Cohort de recebiveis (valor_recebido) por mes_entrada (P1 paga) vs mes_recebido. Apenas assinaturas canonicas.';

-- ============================================================
-- PARTE 4: get_curva_recebiveis_mensal (função NOVA — runway)
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_curva_recebiveis_mensal(p_tenant_id uuid DEFAULT NULL)
RETURNS TABLE(
  mes text,
  tenant_nome text,
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
  )
  SELECT
    e.mes,
    e.tenant_nome,
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
  'Curva de runway de recebiveis: esperado vs realizado mes a mes, com decomposicao em inadimplente e cancelado. Base: previsao_parcelas. Apenas assinaturas canonicas.';
