
-- ─── VIEW: vw_casos_cobranca ──────────────────────────────────
CREATE OR REPLACE VIEW cobranca.vw_casos_cobranca AS
SELECT
  c.contract_id,
  c.tenant_id,
  c.student_id,
  c.voomp_contrato_id,
  s.nome,
  s.cpf_cnpj,
  s.email,
  s.telefone,
  p.nome                                                AS nome_produto,
  c.periodo                                             AS classe,
  t.nome                                                AS tenant_nome,
  c.status_contrato,
  c.recorrencia_total,
  c.data_primeira_venda,
  CASE i.bucket_aging
    WHEN '1_30D'   THEN 'faixa_1'
    WHEN '31_60D'  THEN 'faixa_2'
    WHEN '61_90D'  THEN 'faixa_3'
    WHEN '90PLUS'  THEN 'faixa_4'
    ELSE 'faixa_1'
  END                                                   AS faixa_aging,
  COUNT(i.numero_parcela)                               AS parcelas_vencidas,
  COALESCE(SUM(i.valor_parcela_previsto), 0)            AS valor_total_aberto,
  MAX(i.dias_atraso_voomp)                              AS max_dias_atraso,
  cc.caso_id,
  COALESCE(cc.status, 'em_aberto')                      AS status,
  cc.valor_revertido,
  cc.responsavel,
  cc.data_abertura,
  cc.data_ultima_interacao,
  cc.data_encerramento,
  COUNT(ci.interacao_id)                                AS total_contatos,
  COUNT(ci.interacao_id) FILTER (WHERE ci.houve_retorno) AS total_retornos,
  MAX(ci.data_contato)                                  AS data_ultimo_contato,
  cn.status                                             AS status_negociacao,
  cn.valor_total_acordado                               AS valor_negociado
FROM unipds.contracts c
JOIN unipds.students  s ON s.student_id = c.student_id
JOIN unipds.products  p ON p.product_id = c.product_id
JOIN unipds.tenants   t ON t.tenant_id  = c.tenant_id
JOIN unipds.vw_inadimplencia i ON i.contract_id = c.contract_id
LEFT JOIN cobranca.cobranca_casos       cc ON cc.contract_id = c.contract_id
LEFT JOIN cobranca.cobranca_interacoes  ci ON ci.caso_id     = cc.caso_id
LEFT JOIN cobranca.cobranca_negociacoes cn ON cn.caso_id     = cc.caso_id
                                          AND cn.status      = 'em_andamento'
GROUP BY
  c.contract_id, c.tenant_id, c.student_id, c.voomp_contrato_id,
  s.nome, s.cpf_cnpj, s.email, s.telefone,
  p.nome, c.periodo, t.nome,
  c.status_contrato, c.recorrencia_total, c.data_primeira_venda,
  i.bucket_aging,
  cc.caso_id, cc.status, cc.valor_revertido, cc.responsavel,
  cc.data_abertura, cc.data_ultima_interacao, cc.data_encerramento,
  cn.status, cn.valor_total_acordado;

GRANT SELECT ON cobranca.vw_casos_cobranca TO anon, authenticated, service_role;

-- ─── RPC: get_parcelas_vencidas (reescrita) ───────────────────
CREATE OR REPLACE FUNCTION public.get_parcelas_vencidas(p_contract_id uuid)
RETURNS TABLE (
  previsao_id      uuid,
  previsao_ref     text,
  numero_parcela   integer,
  total_parcelas   integer,
  valor_previsto   numeric,
  data_prevista    date,
  status           text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'unipds'
AS $$
  SELECT
    COALESCE(ct.charge_id, gen_random_uuid()) AS previsao_id,
    ct.voomp_contrato_id                      AS previsao_ref,
    ct.numero_parcela,
    ct.recorrencia_total                      AS total_parcelas,
    ct.valor_parcela_previsto                 AS valor_previsto,
    ct.data_prevista,
    ct.status_parcela                         AS status
  FROM unipds.vw_cronograma_teorico ct
  WHERE ct.contract_id = p_contract_id
    AND ct.status_parcela IN ('VENCIDO', 'EM_ABERTO')
    AND ct.dias_atraso_teorico > 0
  ORDER BY ct.data_prevista ASC;
$$;

GRANT EXECUTE ON FUNCTION public.get_parcelas_vencidas(uuid) TO anon, authenticated, service_role;
