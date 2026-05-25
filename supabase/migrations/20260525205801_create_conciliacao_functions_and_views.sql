
-- ══════════════════════════════════════════════════════════════════
-- Schema conciliacao — Parte 2: funções, views e permissões
-- ══════════════════════════════════════════════════════════════════

-- ── Helper: normalização de nome sem unaccent ──────────────────────
CREATE OR REPLACE FUNCTION conciliacao.normalizar_nome(p_nome text)
RETURNS text LANGUAGE sql IMMUTABLE STRICT AS $$
  SELECT lower(
    regexp_replace(
      translate(
        coalesce(p_nome, ''),
        'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
        'aaaaaeeeeiiiioooooouuuucAAAAAEEEEIIIIoooooUUUUC'
      ),
      '[^a-zA-Z0-9 ]', ' ', 'g'
    )
  )
$$;

-- ── gerar_snapshot_voomp ───────────────────────────────────────────
-- Materializa os contratos Voomp elegíveis para o mês em voomp_snapshot.
-- Critério: venda à vista OU parcela 1 de assinatura com data_pagamento no mês.
-- Idempotente: falha se snapshot já foi gerado (imutabilidade garantida).
CREATE OR REPLACE FUNCTION conciliacao.gerar_snapshot_voomp(
  p_tenant_id uuid,
  p_ano_mes   text
) RETURNS int LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_fechamento_id uuid;
  v_rows          int;
  v_mes_inicio    date := (p_ano_mes || '-01')::date;
  v_mes_fim       date := (p_ano_mes || '-01')::date + interval '1 month';
BEGIN
  SELECT fechamento_id INTO v_fechamento_id
  FROM conciliacao.fechamentos_mensais
  WHERE tenant_id = p_tenant_id AND ano_mes = p_ano_mes;

  IF v_fechamento_id IS NULL THEN
    RAISE EXCEPTION 'Fechamento não encontrado: tenant=%, mes=%', p_tenant_id, p_ano_mes;
  END IF;

  IF EXISTS (
    SELECT 1 FROM conciliacao.voomp_snapshot
    WHERE fechamento_id = v_fechamento_id LIMIT 1
  ) THEN
    RAISE EXCEPTION 'Snapshot já gerado para este mês. Delete o snapshot para regenerar.';
  END IF;

  INSERT INTO conciliacao.voomp_snapshot (
    fechamento_id, tenant_id, ano_mes,
    contract_id, voomp_contrato_id,
    aluno_nome, aluno_nome_norm,
    cpf_cnpj, email,
    produto_nome, tipo_cobranca,
    data_pagamento, valor_cobrado, valor_recebido,
    reembolsado
  )
  WITH primeira_parcela AS (
    SELECT DISTINCT ON (ch.contract_id)
      ch.contract_id,
      ch.tipo_cobranca,
      ch.data_pagamento,
      ch.valor_cobrado,
      ch.valor_recebido,
      ch.categoria
    FROM unipds.charges ch
    WHERE ch.tenant_id = p_tenant_id
      AND ch.categoria IN ('PAGO', 'REEMBOLSADO', 'CHARGEBACK')
      AND ch.data_pagamento IS NOT NULL
      AND ch.data_pagamento >= v_mes_inicio
      AND ch.data_pagamento <  v_mes_fim
      AND (
        ch.tipo_cobranca = 'Único'
        OR (ch.tipo_cobranca = 'Assinatura' AND COALESCE(ch.numero_parcela, 1) = 1)
      )
    ORDER BY
      ch.contract_id,
      CASE ch.categoria WHEN 'PAGO' THEN 0 ELSE 1 END,
      ch.data_pagamento
  )
  SELECT
    v_fechamento_id,
    p_tenant_id,
    p_ano_mes,
    c.contract_id,
    c.voomp_contrato_id,
    s.nome,
    conciliacao.normalizar_nome(s.nome),
    s.cpf_cnpj,
    s.email,
    p.nome,
    pp.tipo_cobranca,
    pp.data_pagamento,
    pp.valor_cobrado,
    pp.valor_recebido,
    (pp.categoria IN ('REEMBOLSADO'))
  FROM primeira_parcela pp
  JOIN unipds.contracts c ON c.contract_id = pp.contract_id
  JOIN unipds.students  s ON s.student_id  = c.student_id
  JOIN unipds.products  p ON p.product_id  = c.product_id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;

  UPDATE conciliacao.fechamentos_mensais
  SET snapshot_gerado_em = now()
  WHERE fechamento_id = v_fechamento_id;

  RETURN v_rows;
END;
$$;

-- ── executar_cruzamento ────────────────────────────────────────────
-- Gera conciliacao_links por CPF (pass 1) e similaridade de nome (pass 2).
-- Links manuais existentes são preservados.
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

  -- Limpar links automáticos anteriores; preservar MANUAL
  DELETE FROM conciliacao.conciliacao_links
  WHERE tenant_id = p_tenant_id
    AND ano_mes = p_ano_mes
    AND criterio <> 'MANUAL';

  -- ── Pass 1: CPF exato ──────────────────────────────────────────
  INSERT INTO conciliacao.conciliacao_links (
    tenant_id, ano_mes, pipe_deal_id, snapshot_id,
    criterio, confianca, divergencia_valor, divergencia_classe
  )
  SELECT DISTINCT ON (pd.pipe_deal_id)
    p_tenant_id, p_ano_mes,
    pd.pipe_deal_id, vs.snapshot_id,
    'AUTO_CPF', 95,
    round((pd.valor - vs.valor_cobrado)::numeric, 2),
    CASE
      WHEN pd.valor = vs.valor_cobrado                                                         THEN 'IDENTICO'
      WHEN abs(pd.valor - vs.valor_cobrado) < 1                                                THEN 'CENTAVOS'
      WHEN abs(pd.valor - vs.valor_cobrado) / NULLIF(pd.valor,0) BETWEEN 0.05 AND 0.20        THEN 'CUPOM_PROVAVEL'
      ELSE 'MATERIAL'
    END
  FROM conciliacao.pipe_deals pd
  JOIN conciliacao.voomp_snapshot vs
    ON vs.fechamento_id = v_fechamento_id
    AND vs.cpf_cnpj = pd.cpf_clean
  WHERE pd.tenant_id = p_tenant_id
    AND pd.ano_mes   = p_ano_mes
    AND pd.status    = 'Ganho'
    AND pd.pipe_deal_id NOT IN (
      SELECT pipe_deal_id FROM conciliacao.conciliacao_links
      WHERE tenant_id = p_tenant_id AND ano_mes = p_ano_mes
    )
    AND vs.snapshot_id NOT IN (
      SELECT snapshot_id FROM conciliacao.conciliacao_links
      WHERE tenant_id = p_tenant_id AND ano_mes = p_ano_mes
    )
  ORDER BY pd.pipe_deal_id, abs(pd.valor - vs.valor_cobrado)
  ON CONFLICT DO NOTHING;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_links := v_links + v_n;

  -- ── Pass 2: similaridade de nome (CPF ausente ou sem match) ───
  INSERT INTO conciliacao.conciliacao_links (
    tenant_id, ano_mes, pipe_deal_id, snapshot_id,
    criterio, confianca, divergencia_valor, divergencia_classe
  )
  SELECT DISTINCT ON (pd.pipe_deal_id)
    p_tenant_id, p_ano_mes,
    pd.pipe_deal_id, vs.snapshot_id,
    'AUTO_NOME', 70,
    round((pd.valor - vs.valor_cobrado)::numeric, 2),
    CASE
      WHEN pd.valor = vs.valor_cobrado                                                         THEN 'IDENTICO'
      WHEN abs(pd.valor - vs.valor_cobrado) < 1                                                THEN 'CENTAVOS'
      WHEN abs(pd.valor - vs.valor_cobrado) / NULLIF(pd.valor,0) BETWEEN 0.05 AND 0.20        THEN 'CUPOM_PROVAVEL'
      ELSE 'MATERIAL'
    END
  FROM conciliacao.pipe_deals pd
  JOIN conciliacao.voomp_snapshot vs
    ON vs.fechamento_id = v_fechamento_id
    AND similarity(pd.pessoa_nome_norm, vs.aluno_nome_norm) > 0.5
    AND abs(pd.valor - vs.valor_cobrado) / NULLIF(pd.valor, 0) < 0.25
  WHERE pd.tenant_id = p_tenant_id
    AND pd.ano_mes   = p_ano_mes
    AND pd.status    = 'Ganho'
    AND pd.pipe_deal_id NOT IN (
      SELECT pipe_deal_id FROM conciliacao.conciliacao_links
      WHERE tenant_id = p_tenant_id AND ano_mes = p_ano_mes
    )
    AND vs.snapshot_id NOT IN (
      SELECT snapshot_id FROM conciliacao.conciliacao_links
      WHERE tenant_id = p_tenant_id AND ano_mes = p_ano_mes
    )
  ORDER BY pd.pipe_deal_id, similarity(pd.pessoa_nome_norm, vs.aluno_nome_norm) DESC
  ON CONFLICT DO NOTHING;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_links := v_links + v_n;

  RETURN v_links;
END;
$$;

-- ── fechar_mes ─────────────────────────────────────────────────────
-- Congela os totais financeiros e muda estado para FECHADO.
CREATE OR REPLACE FUNCTION conciliacao.fechar_mes(
  p_tenant_id uuid,
  p_ano_mes   text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_fechamento_id uuid;
BEGIN
  SELECT fechamento_id INTO v_fechamento_id
  FROM conciliacao.fechamentos_mensais
  WHERE tenant_id = p_tenant_id AND ano_mes = p_ano_mes;

  IF v_fechamento_id IS NULL THEN
    RAISE EXCEPTION 'Fechamento não encontrado: tenant=%, mes=%', p_tenant_id, p_ano_mes;
  END IF;

  UPDATE conciliacao.fechamentos_mensais SET
    estado                      = 'FECHADO',
    fechado_em                  = now(),
    faturamento_pipe_deals      = (
      SELECT count(*) FROM conciliacao.pipe_deals
      WHERE tenant_id = p_tenant_id AND ano_mes = p_ano_mes AND status = 'Ganho'
    ),
    faturamento_pipe_valor      = (
      SELECT coalesce(sum(valor), 0) FROM conciliacao.pipe_deals
      WHERE tenant_id = p_tenant_id AND ano_mes = p_ano_mes AND status = 'Ganho'
    ),
    faturamento_voomp_contratos = (
      SELECT count(*) FROM conciliacao.voomp_snapshot WHERE fechamento_id = v_fechamento_id
    ),
    faturamento_voomp_cobrado   = (
      SELECT coalesce(sum(valor_cobrado), 0) FROM conciliacao.voomp_snapshot WHERE fechamento_id = v_fechamento_id
    ),
    faturamento_voomp_liquido   = (
      SELECT coalesce(sum(valor_recebido), 0) FROM conciliacao.voomp_snapshot WHERE fechamento_id = v_fechamento_id
    ),
    faturamento_voomp_reembolsos = (
      SELECT coalesce(sum(valor_cobrado), 0) FROM conciliacao.voomp_snapshot
      WHERE fechamento_id = v_fechamento_id AND reembolsado = true
    ),
    total_matches               = (
      SELECT count(distinct pipe_deal_id) FROM conciliacao.conciliacao_links
      WHERE tenant_id = p_tenant_id AND ano_mes = p_ano_mes
    ),
    total_orfaos_pipe           = (
      SELECT count(*) FROM conciliacao.pipe_deals pd
      WHERE pd.tenant_id = p_tenant_id AND pd.ano_mes = p_ano_mes AND pd.status = 'Ganho'
        AND pd.pipe_deal_id NOT IN (
          SELECT pipe_deal_id FROM conciliacao.conciliacao_links
          WHERE tenant_id = p_tenant_id AND ano_mes = p_ano_mes
        )
    ),
    total_orfaos_voomp          = (
      SELECT count(*) FROM conciliacao.voomp_snapshot vs
      WHERE vs.fechamento_id = v_fechamento_id
        AND vs.snapshot_id NOT IN (
          SELECT snapshot_id FROM conciliacao.conciliacao_links
          WHERE tenant_id = p_tenant_id AND ano_mes = p_ano_mes
        )
    )
  WHERE fechamento_id = v_fechamento_id;
END;
$$;

-- ── v_cruzamento ───────────────────────────────────────────────────
-- View de trabalho: pipe_deals + voomp_snapshot + status de match.
CREATE OR REPLACE VIEW conciliacao.v_cruzamento AS
  -- Deals Pipe (CASADO ou ORFAO_PIPE)
  SELECT
    pd.tenant_id,
    pd.ano_mes,
    pd.pipe_deal_id,
    vs.snapshot_id,
    CASE WHEN cl.link_id IS NOT NULL THEN 'CASADO' ELSE 'ORFAO_PIPE' END AS status_match,
    pd.pessoa_nome,
    vs.aluno_nome        AS voomp_aluno_nome,
    pd.valor             AS pipe_valor,
    vs.valor_cobrado     AS voomp_valor_cobrado,
    vs.valor_recebido    AS voomp_valor_recebido,
    vs.reembolsado       AS voomp_reembolsado,
    cl.divergencia_valor,
    cl.divergencia_classe,
    cl.criterio,
    cl.confianca,
    vs.data_pagamento    AS voomp_data_pagamento,
    pd.cpf_clean         AS pipe_cpf,
    vs.cpf_cnpj          AS voomp_cpf,
    vs.produto_nome,
    vs.tipo_cobranca,
    cl.link_id
  FROM conciliacao.pipe_deals pd
  LEFT JOIN conciliacao.conciliacao_links cl
    ON cl.tenant_id    = pd.tenant_id
    AND cl.ano_mes     = pd.ano_mes
    AND cl.pipe_deal_id = pd.pipe_deal_id
  LEFT JOIN conciliacao.voomp_snapshot vs
    ON vs.snapshot_id = cl.snapshot_id
  WHERE pd.status = 'Ganho'

  UNION ALL

  -- Contratos Voomp sem match (ORFAO_VOOMP)
  SELECT
    vs.tenant_id,
    vs.ano_mes,
    NULL::bigint         AS pipe_deal_id,
    vs.snapshot_id,
    'ORFAO_VOOMP'        AS status_match,
    NULL                 AS pessoa_nome,
    vs.aluno_nome        AS voomp_aluno_nome,
    NULL::numeric        AS pipe_valor,
    vs.valor_cobrado     AS voomp_valor_cobrado,
    vs.valor_recebido    AS voomp_valor_recebido,
    vs.reembolsado       AS voomp_reembolsado,
    NULL::numeric        AS divergencia_valor,
    NULL                 AS divergencia_classe,
    NULL                 AS criterio,
    NULL::integer        AS confianca,
    vs.data_pagamento    AS voomp_data_pagamento,
    NULL                 AS pipe_cpf,
    vs.cpf_cnpj          AS voomp_cpf,
    vs.produto_nome,
    vs.tipo_cobranca,
    NULL::uuid           AS link_id
  FROM conciliacao.voomp_snapshot vs
  WHERE vs.snapshot_id NOT IN (
    SELECT snapshot_id FROM conciliacao.conciliacao_links
    WHERE tenant_id = vs.tenant_id AND ano_mes = vs.ano_mes
  );

-- ── Permissões ─────────────────────────────────────────────────────
GRANT USAGE ON SCHEMA conciliacao TO anon, authenticated, service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA conciliacao TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA conciliacao TO anon;
GRANT ALL ON ALL TABLES IN SCHEMA conciliacao TO service_role;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA conciliacao TO authenticated, service_role;

-- RLS
ALTER TABLE conciliacao.fechamentos_mensais ENABLE ROW LEVEL SECURITY;
ALTER TABLE conciliacao.pipe_deals          ENABLE ROW LEVEL SECURITY;
ALTER TABLE conciliacao.voomp_snapshot      ENABLE ROW LEVEL SECURITY;
ALTER TABLE conciliacao.conciliacao_links   ENABLE ROW LEVEL SECURITY;
ALTER TABLE conciliacao.ingestao_status     ENABLE ROW LEVEL SECURITY;

-- Política única: usuário autenticado acessa qualquer linha (tenant controlado na app)
CREATE POLICY "authenticated full access" ON conciliacao.fechamentos_mensais FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "authenticated full access" ON conciliacao.pipe_deals          FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "authenticated full access" ON conciliacao.voomp_snapshot      FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "authenticated full access" ON conciliacao.conciliacao_links   FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "authenticated full access" ON conciliacao.ingestao_status     FOR ALL TO authenticated USING (true) WITH CHECK (true);
