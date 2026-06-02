-- ============================================================
-- Inclui voomp_venda_id (ID Venda) no snapshot de conciliacao
--
-- O front precisa do ID Venda para linkar/consultar a venda do lado
-- da Voomp nos detalhes. O snapshot escolhia uma charge por linha mas
-- descartava o voomp_venda_id. Aqui:
--   1. adiciona a coluna voomp_venda_id em voomp_snapshot
--   2. atualiza gerar_snapshot_voomp para gravar ch.voomp_venda_id
--   3. expoe voomp_venda_id em v_cruzamento
--
-- Snapshots ja existentes ficam com voomp_venda_id NULL ate regerar.
-- ============================================================

-- 1) Coluna nova
ALTER TABLE conciliacao.voomp_snapshot
  ADD COLUMN IF NOT EXISTS voomp_venda_id text;

COMMENT ON COLUMN conciliacao.voomp_snapshot.voomp_venda_id IS
  'ID Venda da Voomp (charges.voomp_venda_id) da charge que originou este registro do snapshot.';

-- 2) Funcao atualizada (grava voomp_venda_id)
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
    contract_id, voomp_contrato_id, voomp_venda_id,
    aluno_nome, aluno_nome_norm, cpf_cnpj, email,
    produto_nome, tipo_cobranca,
    data_pagamento, valor_cobrado, valor_recebido, reembolsado
  )
  WITH base AS (
    SELECT
      ch.contract_id, ch.voomp_venda_id, ch.student_id, ch.product_id,
      ch.tipo_cobranca, ch.categoria, ch.data_pagamento,
      ch.valor_cobrado, ch.valor_recebido
    FROM unipds.charges ch
    WHERE ch.tenant_id = p_tenant_id
      AND ch.categoria IN ('PAGO', 'REEMBOLSADO', 'CHARGEBACK')
      AND ch.data_pagamento >= v_mes_inicio
      AND ch.data_pagamento <  v_mes_fim
      AND (
        ch.tipo_cobranca = 'Único'
        OR (ch.tipo_cobranca = 'Assinatura' AND COALESCE(ch.numero_parcela, 1) = 1)
      )
  ),
  dedup AS (
    SELECT DISTINCT ON (COALESCE(contract_id::text, voomp_venda_id)) *
    FROM base
    ORDER BY COALESCE(contract_id::text, voomp_venda_id),
             CASE categoria WHEN 'PAGO' THEN 0 ELSE 1 END,
             data_pagamento
  )
  SELECT
    v_fechamento_id, p_tenant_id, p_ano_mes,
    d.contract_id,
    ct.voomp_contrato_id,
    d.voomp_venda_id,
    s.nome,
    conciliacao.normalizar_nome(s.nome),
    s.cpf_cnpj,
    s.email,
    p.nome,
    d.tipo_cobranca,
    d.data_pagamento,
    CASE WHEN d.tipo_cobranca = 'Assinatura'
         THEN COALESCE(d.valor_recebido, 0) * COALESCE(ct.recorrencia_total, 12)
         ELSE COALESCE(d.valor_recebido, 0)
    END,
    d.valor_recebido,
    (d.categoria = 'REEMBOLSADO')
  FROM dedup d
  JOIN unipds.students  s  ON s.student_id  = d.student_id
  JOIN unipds.products  p  ON p.product_id  = d.product_id
  LEFT JOIN unipds.contracts ct ON ct.contract_id = d.contract_id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;

  UPDATE conciliacao.fechamentos_mensais
  SET snapshot_gerado_em = now()
  WHERE fechamento_id = v_fechamento_id;

  RETURN v_rows;
END;
$$;

COMMENT ON FUNCTION conciliacao.gerar_snapshot_voomp(uuid, text) IS
  'Snapshot Voomp do mes: assinatura P1 + vendas unicas (aluno/produto via charges). Grava voomp_venda_id. valor_cobrado = valor gerencial LIQUIDO comparavel ao Pipe (assinatura: valor_recebido x recorrencia; unica: valor_recebido).';

-- 3) Expor voomp_venda_id na v_cruzamento (DROP+CREATE: muda colunas)
DROP VIEW IF EXISTS conciliacao.v_cruzamento;

CREATE VIEW conciliacao.v_cruzamento AS
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
    cl.link_id
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
    NULL::uuid AS link_id
   FROM conciliacao.voomp_snapshot vs
  WHERE NOT (vs.snapshot_id IN ( SELECT conciliacao_links.snapshot_id
           FROM conciliacao.conciliacao_links
          WHERE conciliacao_links.tenant_id = vs.tenant_id AND conciliacao_links.ano_mes = vs.ano_mes));

GRANT SELECT ON conciliacao.v_cruzamento TO anon, authenticated, service_role;
