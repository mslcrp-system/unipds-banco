-- ============================================================
-- Dashboard de alunos — 2 melhorias pedidas pela mentoria do front
--
-- 1. v_resumo_executivo + tenant_id (no FINAL — regra do
--    CREATE OR REPLACE VIEW): chave ESTAVEL para os cards de
--    tenant. Mata a heuristica por nome ('IA' vs 'UNIPDS
--    INTELIGENCIA ARTIFICIAL') que causava os dois cards "Java".
--    IDs: IA = e717e24d-fb30-4ed0-83d3-bb8ea0b66783
--         Java = 70b668e4-be85-459b-8dbb-3876929ac850
--
-- 2. v_evasao + ocorrido_em / tipo_refund / valor_refund (no
--    FINAL): a data do EVENTO de evasao (refunds.ocorrido_em),
--    mais fiel para tendencia mensal que data_pagamento (quando o
--    aluno pagou). LEFT JOIN seguro: refunds tem UNIQUE por venda
--    (1 refund por charge, nao multiplica linhas). Charges
--    'Reembolso Pendente' podem nao ter refund ainda → front usa
--    COALESCE(ocorrido_em, data_pagamento) para agrupar.
-- ============================================================

-- ─── 1. v_resumo_executivo (+tenant_id) ───────────────────────
CREATE OR REPLACE VIEW unipds.v_resumo_executivo AS
SELECT
    t.nome                              AS tenant,
    COALESCE(m.tipo_curso, 'OUTRO')     AS tipo_curso,
    m.modalidade,
    COUNT(DISTINCT m.student_id)        AS alunos_ativos,
    COUNT(DISTINCT m.contract_ref)      AS contratos_ativos,
    t.tenant_id
FROM unipds.v_matriculas_ativas m
JOIN unipds.tenants t ON t.tenant_id = m.tenant_id
GROUP BY t.tenant_id, t.nome, COALESCE(m.tipo_curso, 'OUTRO'), m.modalidade;

COMMENT ON VIEW unipds.v_resumo_executivo IS
  'Dashboard de alunos: alunos/contratos ativos por tenant x tipo_curso x modalidade. tenant_id exposto como chave estavel (nao usar heuristica por nome).';

GRANT SELECT ON unipds.v_resumo_executivo TO anon, authenticated, service_role;

-- ─── 2. v_evasao (+ocorrido_em, tipo_refund, valor_refund) ────
CREATE OR REPLACE VIEW unipds.v_evasao AS
SELECT
    c.charge_id,
    c.status,
    c.numero_parcela,
    c.metodo_pagamento,
    c.valor_cobrado,
    c.valor_recebido,
    c.data_pagamento,
    COALESCE(ct.voomp_contrato_id, c.voomp_venda_id) AS contract_ref,
    COALESCE(ct.nome_oferta, pr.nome)                AS nome_oferta,
    c.tipo_cobranca,
    ct.recorrencia_total,
    ct.data_primeira_venda,
    c.tenant_id,
    s.nome,
    s.cpf_cnpj,
    t.nome                                           AS tenant_nome,
    r.ocorrido_em::date                              AS ocorrido_em,
    r.tipo                                           AS tipo_refund,
    r.valor                                          AS valor_refund
FROM unipds.charges c
JOIN unipds.students s        ON s.student_id  = c.student_id
JOIN unipds.tenants  t        ON t.tenant_id   = c.tenant_id
LEFT JOIN unipds.contracts ct ON ct.contract_id = c.contract_id
LEFT JOIN unipds.products  pr ON pr.product_id  = c.product_id
LEFT JOIN unipds.refunds   r  ON r.charge_id    = c.charge_id
WHERE c.categoria IN ('REEMBOLSADO', 'CHARGEBACK');

COMMENT ON VIEW unipds.v_evasao IS
  'Dashboard de alunos: charges estornadas/contestadas. ocorrido_em = data do EVENTO de evasao (refunds) — usar COALESCE(ocorrido_em, data_pagamento) para tendencia mensal (Reembolso Pendente pode nao ter refund ainda).';

GRANT SELECT ON unipds.v_evasao TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
