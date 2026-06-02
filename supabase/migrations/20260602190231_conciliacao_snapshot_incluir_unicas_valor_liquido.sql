-- ============================================================
-- Fix conciliacao.gerar_snapshot_voomp
--
-- Dois problemas da versao anterior:
--   (a) INNER JOIN unipds.contracts derrubava TODAS as vendas Único
--       (contract_id NULL) — snapshot vinha so com assinaturas.
--   (b) valor gravado nao batia com o Pipe (que registra o valor
--       LIQUIDO do contrato cheio).
--
-- Correcoes:
--   - Pega aluno/produto direto da charges (student_id/product_id),
--     nao via contrato → vendas unicas entram.
--   - LEFT JOIN contracts (NULL ok para unica).
--   - Dedupe: assinatura por contrato (1 P1); unica por voomp_venda_id.
--   - valor_cobrado (gerencial, comparavel ao Pipe = LIQUIDO):
--       Assinatura → valor_recebido (liquido P1) * recorrencia_total
--       Única      → valor_recebido (liquido)
--     valor_recebido ja desconta taxa Voomp + coproducao (confirmado).
--   - valor_recebido (coluna) = liquido efetivo do mes (parcela).
--
-- Resultado esperado IA maio: 855 registros (556 unicas + 299 P1),
-- contra 299 da versao anterior.
-- ============================================================

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
    -- assinatura: 1 por contrato | unica: 1 por venda
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
    s.nome,
    conciliacao.normalizar_nome(s.nome),
    s.cpf_cnpj,
    s.email,
    p.nome,
    d.tipo_cobranca,
    d.data_pagamento,
    -- valor gerencial LIQUIDO (comparavel ao Pipe)
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
  'Snapshot Voomp do mes: assinatura P1 + vendas unicas (aluno/produto via charges, nao via contrato). valor_cobrado = valor gerencial LIQUIDO comparavel ao Pipe (assinatura: valor_recebido x recorrencia; unica: valor_recebido).';
