
-- ─── 1. get_recebiveis_mensal ───────────────────────────────────────────────
-- Retorna receita recebida por mês e tipo_cobranca (Assinatura / Único)
CREATE OR REPLACE FUNCTION public.get_recebiveis_mensal(p_tenant_id uuid DEFAULT NULL)
RETURNS TABLE(mes text, tipo_cobranca text, receita numeric)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    to_char(ch.data_pagamento, 'YYYY-MM') AS mes,
    ch.tipo_cobranca,
    SUM(ch.valor_recebido)               AS receita
  FROM unipds.charges ch
  WHERE ch.categoria = 'PAGO'
    AND ch.data_pagamento IS NOT NULL
    AND (p_tenant_id IS NULL OR ch.tenant_id = p_tenant_id)
  GROUP BY 1, 2
  ORDER BY 1, 2;
$$;

-- ─── 2. get_curva_recebiveis_mensal ─────────────────────────────────────────
-- Curva de recebíveis: esperado (cronograma teórico) vs realizado/inadimplente/
-- cancelado/saldo_aberto, por mês e tenant.
-- Meses passados = antes do mês corrente; corrente = mês atual; futuro = após.
CREATE OR REPLACE FUNCTION public.get_curva_recebiveis_mensal(p_tenant_id uuid DEFAULT NULL)
RETURNS TABLE(
  mes          text,
  tenant_nome  text,
  status_mes   text,
  esperado     numeric,
  realizado    numeric,
  inadimplente numeric,
  cancelado    numeric,
  saldo_aberto numeric
)
LANGUAGE sql SECURITY DEFINER AS $$
  WITH cronograma AS (
    SELECT
      to_char(ct.data_prevista, 'YYYY-MM')                                         AS mes,
      t.nome                                                                        AS tenant_nome,
      ct.tenant_id,
      SUM(ct.valor_parcela_previsto)                                                AS esperado,
      SUM(CASE WHEN ct.status_parcela = 'PAGA'
               THEN ct.valor_parcela_previsto ELSE 0 END)                           AS realizado_assin,
      SUM(CASE WHEN ct.status_parcela = 'EM_ABERTO'
                AND ct.data_prevista < date_trunc('month', CURRENT_DATE)
               THEN ct.valor_parcela_previsto ELSE 0 END)                           AS inadimplente,
      SUM(CASE WHEN ct.status_parcela IN ('REEMBOLSADA','CHARGEBACK')
               THEN ct.valor_parcela_previsto ELSE 0 END)                           AS cancelado,
      SUM(CASE WHEN ct.status_parcela = 'NAO_EMITIDA'
                OR (ct.status_parcela = 'EM_ABERTO'
                    AND ct.data_prevista >= date_trunc('month', CURRENT_DATE))
               THEN ct.valor_parcela_previsto ELSE 0 END)                           AS saldo_aberto
    FROM unipds.vw_cronograma_teorico ct
    JOIN unipds.tenants t ON t.tenant_id = ct.tenant_id
    WHERE p_tenant_id IS NULL OR ct.tenant_id = p_tenant_id
    GROUP BY to_char(ct.data_prevista, 'YYYY-MM'), t.nome, ct.tenant_id
  ),
  unicas AS (
    SELECT
      to_char(ch.data_pagamento, 'YYYY-MM') AS mes,
      ch.tenant_id,
      SUM(ch.valor_recebido)               AS realizado_unico
    FROM unipds.charges ch
    WHERE ch.tipo_cobranca = 'Único'
      AND ch.categoria = 'PAGO'
      AND ch.data_pagamento IS NOT NULL
      AND (p_tenant_id IS NULL OR ch.tenant_id = p_tenant_id)
    GROUP BY 1, 2
  )
  SELECT
    c.mes,
    c.tenant_nome,
    CASE
      WHEN c.mes < to_char(date_trunc('month', CURRENT_DATE), 'YYYY-MM') THEN 'passado'
      WHEN c.mes = to_char(date_trunc('month', CURRENT_DATE), 'YYYY-MM') THEN 'corrente'
      ELSE 'futuro'
    END                                                    AS status_mes,
    c.esperado,
    c.realizado_assin + COALESCE(u.realizado_unico, 0)    AS realizado,
    c.inadimplente,
    c.cancelado,
    c.saldo_aberto
  FROM cronograma c
  LEFT JOIN unicas u ON u.mes = c.mes AND u.tenant_id = c.tenant_id
  ORDER BY c.mes, c.tenant_nome;
$$;

-- ─── 3. get_cohort_recebiveis ────────────────────────────────────────────────
-- Cohort de assinaturas: por mês de entrada × mês de recebimento
CREATE OR REPLACE FUNCTION public.get_cohort_recebiveis(p_tenant_id uuid DEFAULT NULL)
RETURNS TABLE(mes_entrada text, mes_recebido text, receita numeric, contratos bigint)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    to_char(co.data_primeira_venda, 'YYYY-MM') AS mes_entrada,
    to_char(ch.data_pagamento,      'YYYY-MM') AS mes_recebido,
    SUM(ch.valor_recebido)                     AS receita,
    COUNT(DISTINCT ch.contract_id)             AS contratos
  FROM unipds.charges ch
  JOIN unipds.contracts co ON co.contract_id = ch.contract_id
  WHERE ch.categoria = 'PAGO'
    AND ch.tipo_cobranca = 'Assinatura'
    AND ch.data_pagamento IS NOT NULL
    AND co.data_primeira_venda IS NOT NULL
    AND (p_tenant_id IS NULL OR ch.tenant_id = p_tenant_id)
  GROUP BY 1, 2
  ORDER BY 1, 2;
$$;

-- Permissões para anon/authenticated
GRANT EXECUTE ON FUNCTION public.get_recebiveis_mensal(uuid)        TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_curva_recebiveis_mensal(uuid)  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_cohort_recebiveis(uuid)        TO anon, authenticated;
