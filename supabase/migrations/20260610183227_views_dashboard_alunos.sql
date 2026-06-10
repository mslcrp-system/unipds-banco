-- ============================================================
-- Views do Dashboard de Alunos (times Comunidade + Academico)
--
-- O front (repo dashboard-alunos) espera 3 views em unipds:
--   v_matriculas_ativas, v_resumo_executivo, v_evasao
--
-- Decisoes do mentor sobre o mapeamento proposto pelo front:
--   1. status_contrato para modalidade Unico = constante 'Pago'
--      (a view so contem charges pagas; Unico nao tem contrato).
--   2. contracts.status_contrato NAO normalizado ('failed' fica) —
--      fidelidade ao dado Voomp; rotulo eh preocupacao de exibicao.
--   3. tipo_curso vem de v_produtos_classificados.classe, mas
--      ligado pelo product_id DA PROPRIA MATRICULA (o re-join com
--      charges proposto atribuiria o aluno a toda classe em que ele
--      tivesse qualquer charge, multiplicando a contagem).
--   4. Evasao filtra por categoria IN ('REEMBOLSADO','CHARGEBACK')
--      — verificado: cobre exatamente as mesmas linhas do filtro por
--      status (Reembolsado + Reembolso Pendente + Chargeback) e eh
--      robusto a novos rotulos. A coluna status segue exposta.
--
-- Tambem formaliza v_produtos_classificados (existia no banco sem
-- migration — criada via SQL direto por outra sessao). Definicao
-- identica a de producao.
--
-- Regra de matricula ativa (do front): aluno com >= 1 charge paga
-- (categoria PAGO = status 'Pago') com valor_cobrado > 0.
-- data_matricula = primeiro pagamento da matricula.
-- Chave de matricula: contrato (Assinatura) ou venda (Unico).
-- ============================================================

-- ─── 0. Formalizar v_produtos_classificados (sem mudanca) ─────
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
        WHEN voomp_produto_id = '11972' THEN 'ADMINISTRATIVO'
        ELSE 'OUTRO'
    END AS classe
FROM unipds.products;

GRANT SELECT ON unipds.v_produtos_classificados TO anon, authenticated, service_role;

-- ─── 1. v_matriculas_ativas ───────────────────────────────────
-- 1 linha por matricula (aluno x contrato/venda) com charge paga.
-- DISTINCT ON ordenado por data_pagamento ASC: a primeira charge
-- paga da matricula define data_matricula e o produto.
CREATE OR REPLACE VIEW unipds.v_matriculas_ativas AS
SELECT DISTINCT ON (ch.student_id, COALESCE(ch.contract_id::text, ch.voomp_venda_id))
    ch.student_id,
    s.nome,
    s.cpf_cnpj,
    COALESCE(ct.voomp_contrato_id, ch.voomp_venda_id)  AS contract_ref,
    pr.nome                                            AS produto_nome,
    CASE WHEN ch.tipo_cobranca = 'Único' THEN 'UNICO' ELSE 'ASSINATURA' END AS modalidade,
    ch.data_pagamento                                  AS data_matricula,
    COALESCE(ct.status_contrato, 'Pago')               AS status_contrato,
    ch.tenant_id,
    -- extras (nao exigidos pelo front, uteis p/ resumo e filtros)
    ch.product_id,
    vpc.classe                                         AS tipo_curso
FROM unipds.charges ch
JOIN unipds.students s            ON s.student_id  = ch.student_id
LEFT JOIN unipds.contracts ct     ON ct.contract_id = ch.contract_id
LEFT JOIN unipds.products  pr     ON pr.product_id  = ch.product_id
LEFT JOIN unipds.v_produtos_classificados vpc ON vpc.product_id = ch.product_id
WHERE ch.categoria = 'PAGO'
  AND ch.valor_cobrado > 0
ORDER BY ch.student_id, COALESCE(ch.contract_id::text, ch.voomp_venda_id), ch.data_pagamento ASC;

COMMENT ON VIEW unipds.v_matriculas_ativas IS
  'Dashboard de alunos: 1 linha por matricula com pagamento (categoria PAGO, valor>0). contract_ref = voomp_contrato_id (Assinatura) ou voomp_venda_id (Unico). data_matricula = primeiro pagamento. Unico nao tem contrato: status_contrato=Pago.';

GRANT SELECT ON unipds.v_matriculas_ativas TO anon, authenticated, service_role;

-- ─── 2. v_resumo_executivo ────────────────────────────────────
-- Agrega a partir de v_matriculas_ativas; classe ja vem da propria
-- matricula (sem re-join com charges, sem multiplicacao).
CREATE OR REPLACE VIEW unipds.v_resumo_executivo AS
SELECT
    t.nome                              AS tenant,
    COALESCE(m.tipo_curso, 'OUTRO')     AS tipo_curso,
    m.modalidade,
    COUNT(DISTINCT m.student_id)        AS alunos_ativos,
    COUNT(DISTINCT m.contract_ref)      AS contratos_ativos
FROM unipds.v_matriculas_ativas m
JOIN unipds.tenants t ON t.tenant_id = m.tenant_id
GROUP BY t.nome, COALESCE(m.tipo_curso, 'OUTRO'), m.modalidade;

COMMENT ON VIEW unipds.v_resumo_executivo IS
  'Dashboard de alunos: alunos/contratos ativos por tenant x tipo_curso (v_produtos_classificados.classe) x modalidade.';

GRANT SELECT ON unipds.v_resumo_executivo TO anon, authenticated, service_role;

-- ─── 3. v_evasao ──────────────────────────────────────────────
-- Charges estornadas/contestadas. Filtro por categoria normalizada
-- (cobre Reembolsado, Reembolso Pendente e Chargeback).
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
    t.nome                                           AS tenant_nome
FROM unipds.charges c
JOIN unipds.students s        ON s.student_id  = c.student_id
JOIN unipds.tenants  t        ON t.tenant_id   = c.tenant_id
LEFT JOIN unipds.contracts ct ON ct.contract_id = c.contract_id
LEFT JOIN unipds.products  pr ON pr.product_id  = c.product_id
WHERE c.categoria IN ('REEMBOLSADO', 'CHARGEBACK');

COMMENT ON VIEW unipds.v_evasao IS
  'Dashboard de alunos: charges estornadas/contestadas (categoria REEMBOLSADO ou CHARGEBACK; inclui status Reembolso Pendente). recorrencia_total/data_primeira_venda NULL para Unico.';

GRANT SELECT ON unipds.v_evasao TO anon, authenticated, service_role;

-- Recarrega o cache de tabelas do PostgREST
NOTIFY pgrst, 'reload schema';
