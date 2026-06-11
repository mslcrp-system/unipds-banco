-- ============================================================
-- Conciliacao v2 — travas, auditoria, matching por email,
-- controle cross-tenant. (Solicitacao da sessao front 2026-06-11,
-- revisada e aprovada pelo mentor do banco.)
--
-- Itens:
--   1. Travas de mes FECHADO (guard + triggers nas 3 tabelas de dados)
--   2. Auditoria do CSV Pipe (pipe_imports + pipe_deals.import_id)
--   3. CHECK de criterio ampliado + executar_cruzamento com passe EMAIL
--   4. cross_tenant em links + v_suspeitos_tenant_errado + v_cruzamento
--   5. fechar_mes: orfaos Voomp com exclusao global por snapshot_id
--
-- Ajustes do mentor sobre a proposta:
--   - pipe_imports: +GRANT SELECT para anon (padrao do schema).
--   - Edge case ACEITO: a trava de mes em conciliacao_links valida o
--     mes do TENANT DO DEAL (NEW/OLD.tenant_id). Em link cross-tenant,
--     o mes do tenant do snapshot nao eh checado.
--   - Reabertura de mes: SEM funcao exposta — operacao manual do
--     mentor (UPDATE fechamentos_mensais SET estado='REABERTO').
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- ITEM 1 — Travas de mes fechado
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION conciliacao.assert_mes_aberto(p_tenant_id uuid, p_ano_mes text)
RETURNS void LANGUAGE plpgsql STABLE AS $$
DECLARE v_estado text;
BEGIN
  SELECT estado INTO v_estado
  FROM conciliacao.fechamentos_mensais
  WHERE tenant_id = p_tenant_id AND ano_mes = p_ano_mes;

  IF v_estado = 'FECHADO' THEN
    RAISE EXCEPTION 'Mês % está FECHADO — operação bloqueada. Reabra o fechamento para alterar.', p_ano_mes
      USING ERRCODE = 'P0001';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION conciliacao.tg_bloquear_mes_fechado()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_tenant uuid; v_mes text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_tenant := OLD.tenant_id; v_mes := OLD.ano_mes;
  ELSE
    v_tenant := NEW.tenant_id; v_mes := NEW.ano_mes;
  END IF;
  PERFORM conciliacao.assert_mes_aberto(v_tenant, v_mes);
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS bloquear_mes_fechado ON conciliacao.pipe_deals;
CREATE TRIGGER bloquear_mes_fechado
  BEFORE INSERT OR UPDATE OR DELETE ON conciliacao.pipe_deals
  FOR EACH ROW EXECUTE FUNCTION conciliacao.tg_bloquear_mes_fechado();

DROP TRIGGER IF EXISTS bloquear_mes_fechado ON conciliacao.conciliacao_links;
CREATE TRIGGER bloquear_mes_fechado
  BEFORE INSERT OR UPDATE OR DELETE ON conciliacao.conciliacao_links
  FOR EACH ROW EXECUTE FUNCTION conciliacao.tg_bloquear_mes_fechado();

DROP TRIGGER IF EXISTS bloquear_mes_fechado ON conciliacao.voomp_snapshot;
CREATE TRIGGER bloquear_mes_fechado
  BEFORE INSERT OR UPDATE OR DELETE ON conciliacao.voomp_snapshot
  FOR EACH ROW EXECUTE FUNCTION conciliacao.tg_bloquear_mes_fechado();

-- ────────────────────────────────────────────────────────────
-- ITEM 2 — Auditoria de import do CSV Pipe
-- ────────────────────────────────────────────────────────────

CREATE TABLE conciliacao.pipe_imports (
  import_id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid        NOT NULL REFERENCES unipds.tenants(tenant_id),
  ano_mes            text        NOT NULL CHECK (ano_mes ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  nome_arquivo       text        NOT NULL,
  sha256_hash        text        NOT NULL,
  total_linhas_csv   integer,
  linhas_importadas  integer,
  linhas_descartadas integer,
  descarte_detalhe   jsonb,
  imported_by        uuid,
  imported_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX ON conciliacao.pipe_imports (tenant_id, ano_mes);

ALTER TABLE conciliacao.pipe_deals
  ADD COLUMN import_id uuid REFERENCES conciliacao.pipe_imports(import_id);

GRANT SELECT, INSERT ON conciliacao.pipe_imports TO authenticated;
GRANT SELECT ON conciliacao.pipe_imports TO anon;
GRANT ALL ON conciliacao.pipe_imports TO service_role;
ALTER TABLE conciliacao.pipe_imports ENABLE ROW LEVEL SECURITY;
CREATE POLICY "authenticated full access" ON conciliacao.pipe_imports
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

COMMENT ON TABLE conciliacao.pipe_imports IS
  'Auditoria do CSV comercial (Pipe): hash, contagens e descartes do parser. Preenchida pelo front no full replace. Sem UPDATE/DELETE para authenticated — registro imutavel.';

-- ────────────────────────────────────────────────────────────
-- ITEM 3a — CHECK de criterio ampliado (nome confirmado no banco)
-- ────────────────────────────────────────────────────────────

ALTER TABLE conciliacao.conciliacao_links
  DROP CONSTRAINT conciliacao_links_criterio_check;
ALTER TABLE conciliacao.conciliacao_links
  ADD CONSTRAINT conciliacao_links_criterio_check
  CHECK (criterio IN ('AUTO_CPF','AUTO_EMAIL','AUTO_NOME','MANUAL','CROSS_TENANT'));

-- ────────────────────────────────────────────────────────────
-- ITEM 4a — Coluna cross_tenant
-- ────────────────────────────────────────────────────────────

ALTER TABLE conciliacao.conciliacao_links
  ADD COLUMN cross_tenant boolean NOT NULL DEFAULT false;

-- ────────────────────────────────────────────────────────────
-- ITEM 3b — executar_cruzamento com 3 passes (CPF 95 → EMAIL 85 → NOME 70)
-- ────────────────────────────────────────────────────────────

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

  -- Limpar links automaticos anteriores; preservar MANUAL e CROSS_TENANT
  DELETE FROM conciliacao.conciliacao_links
  WHERE tenant_id = p_tenant_id
    AND ano_mes = p_ano_mes
    AND criterio NOT IN ('MANUAL','CROSS_TENANT');

  -- ── Pass 1: CPF exato (confianca 95) ──
  INSERT INTO conciliacao.conciliacao_links (
    tenant_id, ano_mes, pipe_deal_id, snapshot_id,
    criterio, confianca, divergencia_valor, divergencia_classe
  )
  SELECT DISTINCT ON (pd.pipe_deal_id)
    p_tenant_id, p_ano_mes, pd.pipe_deal_id, vs.snapshot_id,
    'AUTO_CPF', 95,
    round((pd.valor - vs.valor_cobrado)::numeric, 2),
    CASE
      WHEN pd.valor = vs.valor_cobrado                                                  THEN 'IDENTICO'
      WHEN abs(pd.valor - vs.valor_cobrado) < 1                                         THEN 'CENTAVOS'
      WHEN abs(pd.valor - vs.valor_cobrado) / NULLIF(pd.valor,0) BETWEEN 0.05 AND 0.20  THEN 'CUPOM_PROVAVEL'
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

  -- ── Pass 2: EMAIL exato (confianca 85) ──
  INSERT INTO conciliacao.conciliacao_links (
    tenant_id, ano_mes, pipe_deal_id, snapshot_id,
    criterio, confianca, divergencia_valor, divergencia_classe
  )
  SELECT DISTINCT ON (pd.pipe_deal_id)
    p_tenant_id, p_ano_mes, pd.pipe_deal_id, vs.snapshot_id,
    'AUTO_EMAIL', 85,
    round((pd.valor - vs.valor_cobrado)::numeric, 2),
    CASE
      WHEN pd.valor = vs.valor_cobrado                                                  THEN 'IDENTICO'
      WHEN abs(pd.valor - vs.valor_cobrado) < 1                                         THEN 'CENTAVOS'
      WHEN abs(pd.valor - vs.valor_cobrado) / NULLIF(pd.valor,0) BETWEEN 0.05 AND 0.20  THEN 'CUPOM_PROVAVEL'
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

  -- ── Pass 3: similaridade de nome (confianca 70) ──
  INSERT INTO conciliacao.conciliacao_links (
    tenant_id, ano_mes, pipe_deal_id, snapshot_id,
    criterio, confianca, divergencia_valor, divergencia_classe
  )
  SELECT DISTINCT ON (pd.pipe_deal_id)
    p_tenant_id, p_ano_mes, pd.pipe_deal_id, vs.snapshot_id,
    'AUTO_NOME', 70,
    round((pd.valor - vs.valor_cobrado)::numeric, 2),
    CASE
      WHEN pd.valor = vs.valor_cobrado                                                  THEN 'IDENTICO'
      WHEN abs(pd.valor - vs.valor_cobrado) < 1                                         THEN 'CENTAVOS'
      WHEN abs(pd.valor - vs.valor_cobrado) / NULLIF(pd.valor,0) BETWEEN 0.05 AND 0.20  THEN 'CUPOM_PROVAVEL'
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
  'Cruzamento Pipe x Voomp em 3 passes: CPF(95) > EMAIL(85) > NOME~(70). Preserva links MANUAL e CROSS_TENANT. Exclusao de snapshot eh GLOBAL por snapshot_id (consistente com cross-tenant). Bloqueado em mes FECHADO.';

-- ────────────────────────────────────────────────────────────
-- ITEM 4b — View de suspeitos de tenant errado
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW conciliacao.v_suspeitos_tenant_errado AS
SELECT
  pd.tenant_id          AS tenant_pipe,
  vs.tenant_id          AS tenant_voomp,
  pd.ano_mes,
  pd.pipe_deal_id,
  pd.funil,
  pd.proprietario,
  pd.pessoa_nome        AS pipe_nome,
  vs.aluno_nome         AS voomp_nome,
  pd.valor              AS pipe_valor,
  vs.valor_cobrado      AS voomp_valor,
  vs.snapshot_id,
  vs.voomp_venda_id,
  CASE WHEN vs.cpf_cnpj = pd.cpf_clean THEN 'CPF' ELSE 'EMAIL' END AS criterio_suspeita
FROM conciliacao.pipe_deals pd
JOIN conciliacao.voomp_snapshot vs
  ON vs.ano_mes  = pd.ano_mes
  AND vs.tenant_id <> pd.tenant_id
  AND (
    (pd.cpf_clean IS NOT NULL AND vs.cpf_cnpj = pd.cpf_clean)
    OR (pd.email_clean IS NOT NULL AND pd.email_clean <> '' AND lower(trim(vs.email)) = pd.email_clean)
  )
WHERE pd.status = 'Ganho'
  AND NOT EXISTS (SELECT 1 FROM conciliacao.conciliacao_links cl
                  WHERE cl.tenant_id = pd.tenant_id AND cl.ano_mes = pd.ano_mes
                    AND cl.pipe_deal_id = pd.pipe_deal_id)
  AND NOT EXISTS (SELECT 1 FROM conciliacao.conciliacao_links cl
                  WHERE cl.snapshot_id = vs.snapshot_id);

COMMENT ON VIEW conciliacao.v_suspeitos_tenant_errado IS
  'Deal Ganho orfao do tenant A casando por CPF/email com snapshot orfao do tenant B no mesmo mes — provavel deal fechado no funil errado. Vinculo manual: link com criterio=CROSS_TENANT, cross_tenant=true.';

GRANT SELECT ON conciliacao.v_suspeitos_tenant_errado TO anon, authenticated, service_role;

-- ────────────────────────────────────────────────────────────
-- ITEM 4c — v_cruzamento: +cross_tenant, +voomp_tenant_id (ao FINAL)
--           e orfao Voomp com exclusao GLOBAL por snapshot_id
-- ────────────────────────────────────────────────────────────

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
    vs.tenant_id AS voomp_tenant_id
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
    vs.tenant_id AS voomp_tenant_id
   FROM conciliacao.voomp_snapshot vs
  WHERE NOT EXISTS (SELECT 1 FROM conciliacao.conciliacao_links cl
                    WHERE cl.snapshot_id = vs.snapshot_id);

GRANT SELECT ON conciliacao.v_cruzamento TO anon, authenticated, service_role;

-- ────────────────────────────────────────────────────────────
-- ITEM 5 — fechar_mes: orfaos Voomp com exclusao global
-- ────────────────────────────────────────────────────────────

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
        AND NOT EXISTS (SELECT 1 FROM conciliacao.conciliacao_links cl
                        WHERE cl.snapshot_id = vs.snapshot_id)
    )
  WHERE fechamento_id = v_fechamento_id;
END;
$$;

COMMENT ON FUNCTION conciliacao.fechar_mes(uuid, text) IS
  'Congela os totais e muda estado para FECHADO. Orfaos Voomp usam exclusao GLOBAL por snapshot_id (snapshot linkado por deal de outro tenant nao conta como orfao).';

-- Recarrega o cache do PostgREST (tabela e colunas novas)
NOTIFY pgrst, 'reload schema';
