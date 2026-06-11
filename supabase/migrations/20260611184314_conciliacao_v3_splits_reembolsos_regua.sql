-- ============================================================
-- Conciliacao v3 — splits de pagamento, reembolsos visiveis,
-- regua de divergencia com classe PEQUENA.
-- (Adendo da sessao front 2026-06-11, revisado pelo mentor.)
--
-- Achado A: vendas Unico pagas em N cobrancas (2 cartoes) geravam
--   N linhas de snapshot → falso MATERIAL (metade do deal) + falso
--   orfao Voomp (outra metade). Agrupar por (student, product,
--   reembolsado) no mes. Rastro em qtd_cobrancas/vendas_agrupadas.
--   Risco aceito: 2 compras legitimas do mesmo produto no mes sao
--   fundidas (divergencia +100% MATERIAL na revisao detecta).
--
-- Achado B (CORRIGIDO PELO MENTOR): a proposta original trocava o
--   valor gerencial para BRUTO em tudo — quebraria o matching com o
--   Pipe (que registra LIQUIDO; 702/737 IDENTICO na v2 provam).
--   Regra consolidada:
--     PAGO        → gerencial LIQUIDO (assinatura: x recorrencia),
--                   exatamente como v2 — matching preservado.
--     REEMBOLSADO → gerencial BRUTO da(s) cobranca(s), SEM x
--                   recorrencia (o estorno real eh a parcela, nao o
--                   contrato cheio). Card Reembolsos volta a mostrar
--                   ~R$184k em vez de R$0.
--   valor_recebido (coluna) segue sendo o liquido efetivo do mes
--   (reembolsado ja vem 0 da fonte).
--
-- Achado C: classe PEQUENA (>=R$1 e <5%) entre CENTAVOS e CUPOM.
--   Regua monotonica: 0 IDENTICO | <R$1 CENTAVOS | <5% PEQUENA |
--   5-20% CUPOM_PROVAVEL | >20% MATERIAL. Aplicada nos 3 passes.
--
-- Opcional aceito: qtd_cobrancas/vendas_agrupadas expostos na
--   v_cruzamento (ao final das colunas).
-- ============================================================

-- ─── A: colunas de rastro no snapshot ─────────────────────────
ALTER TABLE conciliacao.voomp_snapshot
  ADD COLUMN qtd_cobrancas    integer NOT NULL DEFAULT 1,
  ADD COLUMN vendas_agrupadas text[];

COMMENT ON COLUMN conciliacao.voomp_snapshot.qtd_cobrancas IS
  'Quantas cobrancas Voomp foram agrupadas nesta linha (splits de pagamento de venda Unico).';
COMMENT ON COLUMN conciliacao.voomp_snapshot.vendas_agrupadas IS
  'Todos os voomp_venda_id agrupados (ordem: maior valor primeiro). NULL quando 1 cobranca so.';

-- ─── C: CHECK da regua ampliado (nome confirmado no banco) ────
ALTER TABLE conciliacao.conciliacao_links
  DROP CONSTRAINT conciliacao_links_divergencia_classe_check;
ALTER TABLE conciliacao.conciliacao_links
  ADD CONSTRAINT conciliacao_links_divergencia_classe_check
  CHECK (divergencia_classe IN ('IDENTICO','CENTAVOS','PEQUENA','CUPOM_PROVAVEL','MATERIAL'));

-- ─── A+B: gerar_snapshot_voomp v3 ─────────────────────────────
CREATE OR REPLACE FUNCTION conciliacao.gerar_snapshot_voomp(
  p_tenant_id uuid,
  p_ano_mes   text
) RETURNS int LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE
  v_fechamento_id uuid;
  v_rows          int;
  v_mes_inicio    date := (p_ano_mes || '-01')::date;
  v_mes_fim       date := ((p_ano_mes || '-01')::date + interval '1 month')::date;
BEGIN
  SELECT fechamento_id INTO v_fechamento_id
  FROM conciliacao.fechamentos_mensais
  WHERE tenant_id = p_tenant_id AND ano_mes = p_ano_mes;

  IF v_fechamento_id IS NULL THEN
    RAISE EXCEPTION 'Fechamento não encontrado: tenant=%, mes=%', p_tenant_id, p_ano_mes;
  END IF;

  IF EXISTS (SELECT 1 FROM conciliacao.voomp_snapshot WHERE fechamento_id = v_fechamento_id LIMIT 1) THEN
    RAISE EXCEPTION 'Snapshot já gerado para este mês. Delete o snapshot para regenerar.';
  END IF;

  PERFORM conciliacao.assert_mes_aberto(p_tenant_id, p_ano_mes);

  INSERT INTO conciliacao.voomp_snapshot (
    fechamento_id, tenant_id, ano_mes, contract_id, voomp_contrato_id,
    aluno_nome, aluno_nome_norm, cpf_cnpj, email, produto_nome, tipo_cobranca,
    data_pagamento, valor_cobrado, valor_recebido, reembolsado,
    voomp_venda_id, qtd_cobrancas, vendas_agrupadas
  )
  WITH base AS (
    SELECT ch.*
    FROM unipds.charges ch
    WHERE ch.tenant_id = p_tenant_id
      AND ch.categoria IN ('PAGO','REEMBOLSADO','CHARGEBACK')
      AND ch.data_pagamento IS NOT NULL
      AND ch.data_pagamento >= v_mes_inicio
      AND ch.data_pagamento <  v_mes_fim
  ),
  -- Assinatura: P1, dedup por contrato com prioridade PAGO
  assinatura AS (
    SELECT DISTINCT ON (b.contract_id)
      b.contract_id, b.student_id, b.product_id,
      'Assinatura'::text AS tipo_cobranca,
      b.data_pagamento,
      b.valor_cobrado   AS bruto,
      b.valor_recebido  AS liquido,
      (b.categoria = 'REEMBOLSADO') AS reembolsado,
      b.voomp_venda_id,
      1::int AS qtd_cobrancas,
      NULL::text[] AS vendas_agrupadas
    FROM base b
    WHERE b.tipo_cobranca = 'Assinatura' AND COALESCE(b.numero_parcela, 1) = 1
    ORDER BY b.contract_id,
             CASE b.categoria WHEN 'PAGO' THEN 0 ELSE 1 END,
             b.data_pagamento
  ),
  -- Unico: AGRUPADO por aluno+produto+situacao (Achado A)
  unico AS (
    SELECT
      NULL::uuid AS contract_id,
      b.student_id, b.product_id,
      'Único'::text AS tipo_cobranca,
      min(b.data_pagamento)  AS data_pagamento,
      sum(b.valor_cobrado)   AS bruto,
      sum(b.valor_recebido)  AS liquido,
      (b.categoria = 'REEMBOLSADO') AS reembolsado,
      (array_agg(b.voomp_venda_id ORDER BY b.valor_cobrado DESC))[1] AS voomp_venda_id,
      count(*)::int AS qtd_cobrancas,
      CASE WHEN count(*) > 1
           THEN array_agg(b.voomp_venda_id ORDER BY b.valor_cobrado DESC)
           ELSE NULL END AS vendas_agrupadas
    FROM base b
    WHERE b.tipo_cobranca = 'Único'
    GROUP BY b.student_id, b.product_id, (b.categoria = 'REEMBOLSADO')
  ),
  unificado AS (
    SELECT * FROM assinatura
    UNION ALL
    SELECT * FROM unico
  )
  SELECT
    v_fechamento_id, p_tenant_id, p_ano_mes,
    u.contract_id, c.voomp_contrato_id,
    s.nome, conciliacao.normalizar_nome(s.nome), s.cpf_cnpj, s.email,
    p.nome, u.tipo_cobranca, u.data_pagamento,
    -- Valor gerencial (Achado B, regra do mentor):
    --   reembolsado  → BRUTO da(s) cobranca(s), sem x recorrencia
    --   pago         → LIQUIDO (assinatura: x recorrencia) — matching Pipe
    CASE
      WHEN u.reembolsado THEN u.bruto
      WHEN u.tipo_cobranca = 'Assinatura'
           THEN COALESCE(u.liquido, 0) * COALESCE(c.recorrencia_total, 12)
      ELSE COALESCE(u.liquido, 0)
    END,
    -- Liquido efetivo do mes (reembolsado ja vem 0 da fonte)
    u.liquido,
    u.reembolsado,
    u.voomp_venda_id, u.qtd_cobrancas, u.vendas_agrupadas
  FROM unificado u
  LEFT JOIN unipds.contracts c ON c.contract_id = u.contract_id
  JOIN unipds.students  s ON s.student_id = u.student_id
  JOIN unipds.products  p ON p.product_id = u.product_id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;

  UPDATE conciliacao.fechamentos_mensais
  SET snapshot_gerado_em = now()
  WHERE fechamento_id = v_fechamento_id;

  RETURN v_rows;
END;
$function$;

COMMENT ON FUNCTION conciliacao.gerar_snapshot_voomp(uuid, text) IS
  'Snapshot v3: assinatura P1 (dedup) + Unico AGRUPADO por aluno/produto/situacao (funde splits; rastro em qtd_cobrancas/vendas_agrupadas). Valor gerencial: pago=LIQUIDO (assinatura x recorrencia, matching Pipe); reembolsado=BRUTO sem multiplicar (card Reembolsos).';

-- ─── C: executar_cruzamento com regua de 5 classes ────────────
CREATE OR REPLACE FUNCTION conciliacao.executar_cruzamento(
  p_tenant_id uuid,
  p_ano_mes   text
) RETURNS int LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_fechamento_id uuid;
  v_links         int := 0;
  v_n             int;
BEGIN
  SELECT fechamento_id INTO v_fechamento_id
  FROM conciliacao.fechamentos_mensais
  WHERE tenant_id = p_tenant_id AND ano_mes = p_ano_mes;

  IF v_fechamento_id IS NULL THEN
    RAISE EXCEPTION 'Fechamento não encontrado: tenant=%, mes=%', p_tenant_id, p_ano_mes;
  END IF;

  PERFORM conciliacao.assert_mes_aberto(p_tenant_id, p_ano_mes);

  DELETE FROM conciliacao.conciliacao_links
  WHERE tenant_id = p_tenant_id
    AND ano_mes = p_ano_mes
    AND criterio NOT IN ('MANUAL','CROSS_TENANT');

  -- ── Pass 1: CPF exato (95) ──
  INSERT INTO conciliacao.conciliacao_links (
    tenant_id, ano_mes, pipe_deal_id, snapshot_id,
    criterio, confianca, divergencia_valor, divergencia_classe
  )
  SELECT DISTINCT ON (pd.pipe_deal_id)
    p_tenant_id, p_ano_mes, pd.pipe_deal_id, vs.snapshot_id,
    'AUTO_CPF', 95,
    round((pd.valor - vs.valor_cobrado)::numeric, 2),
    CASE
      WHEN pd.valor = vs.valor_cobrado                                       THEN 'IDENTICO'
      WHEN abs(pd.valor - vs.valor_cobrado) < 1                              THEN 'CENTAVOS'
      WHEN abs(pd.valor - vs.valor_cobrado) / NULLIF(pd.valor,0) < 0.05      THEN 'PEQUENA'
      WHEN abs(pd.valor - vs.valor_cobrado) / NULLIF(pd.valor,0) <= 0.20     THEN 'CUPOM_PROVAVEL'
      ELSE 'MATERIAL'
    END
  FROM conciliacao.pipe_deals pd
  JOIN conciliacao.voomp_snapshot vs
    ON vs.fechamento_id = v_fechamento_id
    AND vs.cpf_cnpj = pd.cpf_clean
  WHERE pd.tenant_id = p_tenant_id AND pd.ano_mes = p_ano_mes AND pd.status = 'Ganho'
    AND pd.cpf_clean IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM conciliacao.conciliacao_links cl
                    WHERE cl.tenant_id = p_tenant_id AND cl.ano_mes = p_ano_mes
                      AND cl.pipe_deal_id = pd.pipe_deal_id)
    AND NOT EXISTS (SELECT 1 FROM conciliacao.conciliacao_links cl
                    WHERE cl.snapshot_id = vs.snapshot_id)
  ORDER BY pd.pipe_deal_id, abs(pd.valor - vs.valor_cobrado)
  ON CONFLICT DO NOTHING;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_links := v_links + v_n;

  -- ── Pass 2: EMAIL exato (85) ──
  INSERT INTO conciliacao.conciliacao_links (
    tenant_id, ano_mes, pipe_deal_id, snapshot_id,
    criterio, confianca, divergencia_valor, divergencia_classe
  )
  SELECT DISTINCT ON (pd.pipe_deal_id)
    p_tenant_id, p_ano_mes, pd.pipe_deal_id, vs.snapshot_id,
    'AUTO_EMAIL', 85,
    round((pd.valor - vs.valor_cobrado)::numeric, 2),
    CASE
      WHEN pd.valor = vs.valor_cobrado                                       THEN 'IDENTICO'
      WHEN abs(pd.valor - vs.valor_cobrado) < 1                              THEN 'CENTAVOS'
      WHEN abs(pd.valor - vs.valor_cobrado) / NULLIF(pd.valor,0) < 0.05      THEN 'PEQUENA'
      WHEN abs(pd.valor - vs.valor_cobrado) / NULLIF(pd.valor,0) <= 0.20     THEN 'CUPOM_PROVAVEL'
      ELSE 'MATERIAL'
    END
  FROM conciliacao.pipe_deals pd
  JOIN conciliacao.voomp_snapshot vs
    ON vs.fechamento_id = v_fechamento_id
    AND lower(trim(vs.email)) = pd.email_clean
  WHERE pd.tenant_id = p_tenant_id AND pd.ano_mes = p_ano_mes AND pd.status = 'Ganho'
    AND pd.email_clean IS NOT NULL AND pd.email_clean <> ''
    AND NOT EXISTS (SELECT 1 FROM conciliacao.conciliacao_links cl
                    WHERE cl.tenant_id = p_tenant_id AND cl.ano_mes = p_ano_mes
                      AND cl.pipe_deal_id = pd.pipe_deal_id)
    AND NOT EXISTS (SELECT 1 FROM conciliacao.conciliacao_links cl
                    WHERE cl.snapshot_id = vs.snapshot_id)
  ORDER BY pd.pipe_deal_id, abs(pd.valor - vs.valor_cobrado)
  ON CONFLICT DO NOTHING;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_links := v_links + v_n;

  -- ── Pass 3: similaridade de nome (70) ──
  INSERT INTO conciliacao.conciliacao_links (
    tenant_id, ano_mes, pipe_deal_id, snapshot_id,
    criterio, confianca, divergencia_valor, divergencia_classe
  )
  SELECT DISTINCT ON (pd.pipe_deal_id)
    p_tenant_id, p_ano_mes, pd.pipe_deal_id, vs.snapshot_id,
    'AUTO_NOME', 70,
    round((pd.valor - vs.valor_cobrado)::numeric, 2),
    CASE
      WHEN pd.valor = vs.valor_cobrado                                       THEN 'IDENTICO'
      WHEN abs(pd.valor - vs.valor_cobrado) < 1                              THEN 'CENTAVOS'
      WHEN abs(pd.valor - vs.valor_cobrado) / NULLIF(pd.valor,0) < 0.05      THEN 'PEQUENA'
      WHEN abs(pd.valor - vs.valor_cobrado) / NULLIF(pd.valor,0) <= 0.20     THEN 'CUPOM_PROVAVEL'
      ELSE 'MATERIAL'
    END
  FROM conciliacao.pipe_deals pd
  JOIN conciliacao.voomp_snapshot vs
    ON vs.fechamento_id = v_fechamento_id
    AND similarity(pd.pessoa_nome_norm, vs.aluno_nome_norm) > 0.5
    AND abs(pd.valor - vs.valor_cobrado) / NULLIF(pd.valor, 0) < 0.25
  WHERE pd.tenant_id = p_tenant_id AND pd.ano_mes = p_ano_mes AND pd.status = 'Ganho'
    AND NOT EXISTS (SELECT 1 FROM conciliacao.conciliacao_links cl
                    WHERE cl.tenant_id = p_tenant_id AND cl.ano_mes = p_ano_mes
                      AND cl.pipe_deal_id = pd.pipe_deal_id)
    AND NOT EXISTS (SELECT 1 FROM conciliacao.conciliacao_links cl
                    WHERE cl.snapshot_id = vs.snapshot_id)
  ORDER BY pd.pipe_deal_id, similarity(pd.pessoa_nome_norm, vs.aluno_nome_norm) DESC
  ON CONFLICT DO NOTHING;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_links := v_links + v_n;

  RETURN v_links;
END;
$$;

COMMENT ON FUNCTION conciliacao.executar_cruzamento(uuid, text) IS
  'Cruzamento 3 passes: CPF(95) > EMAIL(85) > NOME~(70). Regua: 0 IDENTICO | <R$1 CENTAVOS | <5% PEQUENA | 5-20% CUPOM_PROVAVEL | >20% MATERIAL. Preserva MANUAL/CROSS_TENANT. Bloqueado em mes FECHADO.';

-- ─── Opcional: expor rastro de splits na v_cruzamento (ao final) ─
CREATE OR REPLACE VIEW conciliacao.v_cruzamento AS
  SELECT pd.tenant_id,
    pd.ano_mes,
    pd.pipe_deal_id,
    vs.snapshot_id,
    CASE WHEN cl.link_id IS NOT NULL THEN 'CASADO'::text ELSE 'ORFAO_PIPE'::text END AS status_match,
    pd.pessoa_nome,
    vs.aluno_nome AS voomp_aluno_nome,
    pd.valor AS pipe_valor,
    vs.valor_cobrado AS voomp_valor_cobrado,
    vs.valor_recebido AS voomp_valor_recebido,
    vs.reembolsado AS voomp_reembolsado,
    cl.divergencia_valor,
    cl.divergencia_classe,
    cl.criterio,
    cl.confianca,
    vs.data_pagamento AS voomp_data_pagamento,
    pd.cpf_clean AS pipe_cpf,
    vs.cpf_cnpj AS voomp_cpf,
    vs.produto_nome,
    vs.tipo_cobranca,
    vs.voomp_contrato_id,
    vs.voomp_venda_id,
    cl.link_id,
    cl.cross_tenant,
    vs.tenant_id AS voomp_tenant_id,
    vs.qtd_cobrancas,
    vs.vendas_agrupadas
   FROM conciliacao.pipe_deals pd
     LEFT JOIN conciliacao.conciliacao_links cl ON cl.tenant_id = pd.tenant_id AND cl.ano_mes = pd.ano_mes AND cl.pipe_deal_id = pd.pipe_deal_id
     LEFT JOIN conciliacao.voomp_snapshot vs ON vs.snapshot_id = cl.snapshot_id
  WHERE pd.status = 'Ganho'::text
UNION ALL
 SELECT vs.tenant_id,
    vs.ano_mes,
    NULL::bigint AS pipe_deal_id,
    vs.snapshot_id,
    'ORFAO_VOOMP'::text AS status_match,
    NULL::text AS pessoa_nome,
    vs.aluno_nome AS voomp_aluno_nome,
    NULL::numeric AS pipe_valor,
    vs.valor_cobrado AS voomp_valor_cobrado,
    vs.valor_recebido AS voomp_valor_recebido,
    vs.reembolsado AS voomp_reembolsado,
    NULL::numeric AS divergencia_valor,
    NULL::text AS divergencia_classe,
    NULL::text AS criterio,
    NULL::integer AS confianca,
    vs.data_pagamento AS voomp_data_pagamento,
    NULL::text AS pipe_cpf,
    vs.cpf_cnpj AS voomp_cpf,
    vs.produto_nome,
    vs.tipo_cobranca,
    vs.voomp_contrato_id,
    vs.voomp_venda_id,
    NULL::uuid AS link_id,
    NULL::boolean AS cross_tenant,
    vs.tenant_id AS voomp_tenant_id,
    vs.qtd_cobrancas,
    vs.vendas_agrupadas
   FROM conciliacao.voomp_snapshot vs
  WHERE NOT EXISTS (SELECT 1 FROM conciliacao.conciliacao_links cl
                    WHERE cl.snapshot_id = vs.snapshot_id);

GRANT SELECT ON conciliacao.v_cruzamento TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
