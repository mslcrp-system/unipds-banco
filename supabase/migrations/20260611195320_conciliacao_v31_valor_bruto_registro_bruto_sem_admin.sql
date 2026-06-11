-- ============================================================
-- Conciliacao v3.1 — valor_bruto na fotografia, sentinela de
-- registro em bruto, exclusao de produtos administrativos (multas).
-- (Adendo expandido da sessao front 2026-06-11, AUDITADO pelo mentor.)
--
-- AUDITORIA DO MENTOR (dados de maio/IA):
--   Achado D REFUTADO: 246/265 assinaturas casadas (92,8%) sao
--   IDENTICO contra o liquido cheio; o exemplo do adendo (5.200,68)
--   EH o liquido cheio (433,39x12), nao o bruto (6.000). Os CUPOM de
--   assinatura tem divergencia MEDIA NEGATIVA (-670 = desconto), nao
--   +12%. O comercial ja registra LIQUIDO nos dois tipos e a base de
--   matching ja eh liquida desde a v2 — transicao/corte desnecessarios.
--   registro_bruto entra como SENTINELA (esperado ~0 hoje).
--
--   B2/B3: diagnostico correto (a taxa nao aparece na fotografia),
--   remedio incorreto (trocar colunas quebraria o matching). Solucao:
--   coluna NOVA valor_bruto. valor_recebido segue sendo o liquido
--   efetivo DO MES (1 parcela em assinatura) — por design.
--
--   Achado E confirmado: produto 12229 (Multa 20% Extensao IA) estava
--   classe OUTRO; demais multas + "Negociacao Java" (10908) ja eram
--   ADMINISTRATIVO.
--
-- Mudancas:
--   E1. v_produtos_classificados: 12229 -> ADMINISTRATIVO
--   E2. gerar_snapshot_voomp: exclui classe ADMINISTRATIVO (multas/
--       negociacoes nao sao venda; consulta propria fora deste fluxo)
--   B2'. voomp_snapshot.valor_bruto (novo): bruto cheio
--        (Unico: soma cobrado; Assinatura: cobrado_P1 x recorrencia;
--         reembolsado: soma cobrado, sem multiplicar)
--   D1. conciliacao_links.divergencia_liquido + registro_bruto
--   D2'. executar_cruzamento calcula ambos nos 3 passes:
--        divergencia_liquido = pd.valor - vs.valor_cobrado (vs base
--          liquida cheia; p/ pagos equivale a divergencia_valor —
--          existe pela semantica explicita do relatorio de comissao)
--        registro_bruto = casou ao centavo com o BRUTO cheio numa
--          venda com taxa (sentinela de registro errado no Pipe)
--   D3. v_cruzamento: +divergencia_liquido, +registro_bruto,
--       +voomp_valor_bruto (ao final)
-- ============================================================

-- ─── E1: reclassificar 12229 como ADMINISTRATIVO ──────────────
CREATE OR REPLACE VIEW unipds.v_produtos_classificados AS
SELECT product_id,
    voomp_produto_id,
    nome,
    tipo,
    CASE
        WHEN voomp_produto_id = ANY (ARRAY['7724','7852','13761','13762','12663']) THEN 'POS_GRADUACAO'
        WHEN voomp_produto_id = ANY (ARRAY['7725','7856']) THEN 'EXTENSAO'
        WHEN voomp_produto_id = ANY (ARRAY['9752','12228','10908']) THEN 'ADMINISTRATIVO'
        WHEN voomp_produto_id = ANY (ARRAY['11957','11971','12657','12658','12882','13459','13764','13766']) THEN 'POS_GRADUACAO'
        WHEN voomp_produto_id = ANY (ARRAY['11973','11974','13497','14164']) THEN 'EXTENSAO'
        WHEN voomp_produto_id = ANY (ARRAY['11972','12229']) THEN 'ADMINISTRATIVO'
        ELSE 'OUTRO'
    END AS classe
FROM unipds.products;

GRANT SELECT ON unipds.v_produtos_classificados TO anon, authenticated, service_role;

-- ─── B2'/D1: colunas novas ─────────────────────────────────────
ALTER TABLE conciliacao.voomp_snapshot
  ADD COLUMN valor_bruto numeric(15,2);

COMMENT ON COLUMN conciliacao.voomp_snapshot.valor_bruto IS
  'Bruto cheio gerencial: Unico = soma do cobrado; Assinatura = cobrado da P1 x recorrencia; reembolsado = soma do cobrado (sem multiplicar). A taxa da fotografia = valor_bruto - valor_cobrado (pagos).';

ALTER TABLE conciliacao.conciliacao_links
  ADD COLUMN divergencia_liquido numeric(15,2),
  ADD COLUMN registro_bruto      boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN conciliacao.conciliacao_links.registro_bruto IS
  'SENTINELA: deal casou ao centavo com o BRUTO cheio numa venda com taxa — comercial registrou o cobrado em vez do liquido. Auditoria 06/2026: pratica ja era liquida (esperado ~0).';

-- ─── E2 + B2': gerar_snapshot_voomp v3.1 ──────────────────────
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
    voomp_venda_id, qtd_cobrancas, vendas_agrupadas, valor_bruto
  )
  WITH base AS (
    SELECT ch.*
    FROM unipds.charges ch
    WHERE ch.tenant_id = p_tenant_id
      AND ch.categoria IN ('PAGO','REEMBOLSADO','CHARGEBACK')
      AND ch.data_pagamento IS NOT NULL
      AND ch.data_pagamento >= v_mes_inicio
      AND ch.data_pagamento <  v_mes_fim
      -- E2: multa/negociacao (ADMINISTRATIVO) nao eh venda — fora da fotografia
      AND NOT EXISTS (
        SELECT 1 FROM unipds.v_produtos_classificados vc
        WHERE vc.product_id = ch.product_id
          AND vc.classe = 'ADMINISTRATIVO'
      )
  ),
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
    -- Valor gerencial (base de matching): pago=LIQUIDO cheio; reembolsado=BRUTO parcela
    CASE
      WHEN u.reembolsado THEN u.bruto
      WHEN u.tipo_cobranca = 'Assinatura'
           THEN COALESCE(u.liquido, 0) * COALESCE(c.recorrencia_total, 12)
      ELSE COALESCE(u.liquido, 0)
    END,
    -- Liquido efetivo do mes
    u.liquido,
    u.reembolsado,
    u.voomp_venda_id, u.qtd_cobrancas, u.vendas_agrupadas,
    -- B2': BRUTO cheio gerencial (a taxa volta a ser visivel na fotografia)
    CASE
      WHEN u.reembolsado THEN u.bruto
      WHEN u.tipo_cobranca = 'Assinatura'
           THEN COALESCE(u.bruto, 0) * COALESCE(c.recorrencia_total, 12)
      ELSE COALESCE(u.bruto, 0)
    END
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
  'Snapshot v3.1: assinatura P1 (dedup) + Unico agrupado (splits). Exclui produtos ADMINISTRATIVO (multas/negociacoes). valor_cobrado=liquido cheio (matching Pipe); valor_bruto=bruto cheio; valor_recebido=liquido do mes; reembolsado=bruto parcela.';

-- ─── D2': executar_cruzamento com divergencia_liquido + registro_bruto ─
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
    criterio, confianca, divergencia_valor, divergencia_classe,
    divergencia_liquido, registro_bruto
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
    END,
    round((pd.valor - vs.valor_cobrado)::numeric, 2),
    (abs(pd.valor - COALESCE(vs.valor_bruto,0)) < 1
     AND COALESCE(vs.valor_bruto,0) - vs.valor_cobrado >= 1)
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
    criterio, confianca, divergencia_valor, divergencia_classe,
    divergencia_liquido, registro_bruto
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
    END,
    round((pd.valor - vs.valor_cobrado)::numeric, 2),
    (abs(pd.valor - COALESCE(vs.valor_bruto,0)) < 1
     AND COALESCE(vs.valor_bruto,0) - vs.valor_cobrado >= 1)
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
    criterio, confianca, divergencia_valor, divergencia_classe,
    divergencia_liquido, registro_bruto
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
    END,
    round((pd.valor - vs.valor_cobrado)::numeric, 2),
    (abs(pd.valor - COALESCE(vs.valor_bruto,0)) < 1
     AND COALESCE(vs.valor_bruto,0) - vs.valor_cobrado >= 1)
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
  'Cruzamento 3 passes: CPF(95) > EMAIL(85) > NOME~(70). Regua 5 classes. Calcula divergencia_liquido (vs liquido cheio; p/ pagos equivale a divergencia_valor) e registro_bruto (sentinela: casou com o BRUTO cheio). Preserva MANUAL/CROSS_TENANT. Bloqueado em mes FECHADO.';

-- ─── D3: v_cruzamento +3 colunas (ao final) ────────────────────
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
    vs.vendas_agrupadas,
    cl.divergencia_liquido,
    cl.registro_bruto,
    vs.valor_bruto AS voomp_valor_bruto
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
    vs.vendas_agrupadas,
    NULL::numeric AS divergencia_liquido,
    NULL::boolean AS registro_bruto,
    vs.valor_bruto AS voomp_valor_bruto
   FROM conciliacao.voomp_snapshot vs
  WHERE NOT EXISTS (SELECT 1 FROM conciliacao.conciliacao_links cl
                    WHERE cl.snapshot_id = vs.snapshot_id);

GRANT SELECT ON conciliacao.v_cruzamento TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
