-- ============================================================
-- View cobranca.vw_reversoes
--
-- Atribui REVERSAO ao time de contato: quando um caso teve pelo
-- menos 1 interacao e o aluno pagou alguma parcela DEPOIS do
-- primeiro contato, esse valor conta como reversao do time.
--
-- Filosofia (definida pelo dono): o esforco eh contactar/lembrar o
-- aluno. Se houve contato e em seguida pagamento, a acao reverteu
-- a inadimplencia — independente do operador clicar "Fechar como pago".
--
-- Regras:
--   - Apenas casos COM >= 1 interacao registrada (JOIN obrigatorio)
--   - Corte = data do PRIMEIRO contato (MIN data_contato)
--   - Conta charges PAGO do MESMO contrato com data_pagamento >=
--     data_primeira_interacao
--   - Valor BRUTO (valor_cobrado) — a divida que saiu da inadimplencia
--   - Retroativo: calcula tudo; o dashboard filtra periodo por
--     data_ultimo_pagamento_pos_contato
--   - Valor real pago (nao usa o valor_revertido manual). Se operador
--     digitou 1500 e entraram 500, mostra 500 (a verdade do caixa).
--
-- IMPORTANTE: substitui a leitura via vw_casos_cobranca (que faz
-- INNER JOIN com inadimplencia e PERDE casos ja quitados — escondia
-- justamente as reversoes bem-sucedidas). Esta view parte de
-- cobranca_casos e nunca perde um caso resolvido.
-- ============================================================

CREATE OR REPLACE VIEW cobranca.vw_reversoes AS
WITH primeiro_contato AS (
    SELECT
        ci.caso_id,
        MIN(ci.data_contato) AS data_primeira_interacao,
        MAX(ci.data_contato) AS data_ultima_interacao,
        COUNT(*)             AS total_interacoes,
        COUNT(*) FILTER (WHERE ci.houve_retorno) AS interacoes_com_retorno
    FROM cobranca.cobranca_interacoes ci
    GROUP BY ci.caso_id
),
pagamentos_pos_contato AS (
    SELECT
        pc.caso_id,
        SUM(ch.valor_cobrado)  AS valor_revertido,
        COUNT(*)               AS parcelas_revertidas,
        MAX(ch.data_pagamento) AS data_ultimo_pagamento
    FROM primeiro_contato pc
    JOIN cobranca.cobranca_casos cc ON cc.caso_id = pc.caso_id
    JOIN unipds.charges ch
        ON ch.contract_id   = cc.contract_id
       AND ch.categoria     = 'PAGO'
       AND ch.data_pagamento >= pc.data_primeira_interacao
    GROUP BY pc.caso_id
)
SELECT
    cc.caso_id,
    cc.contract_id,
    cc.tenant_id,
    t.nome              AS tenant_nome,
    c.voomp_contrato_id,
    s.student_id,
    s.nome              AS aluno_nome,
    s.cpf_cnpj,
    s.email,
    s.telefone,
    p.nome              AS produto_nome,
    cc.status           AS status_caso,
    cc.responsavel,
    cc.data_abertura,
    pc.data_primeira_interacao,
    pc.data_ultima_interacao,
    pc.total_interacoes,
    pc.interacoes_com_retorno,
    -- Reversao atribuida (valor real pago apos o primeiro contato)
    COALESCE(pp.valor_revertido, 0)        AS valor_revertido,
    COALESCE(pp.parcelas_revertidas, 0)    AS parcelas_revertidas,
    pp.data_ultimo_pagamento               AS data_ultimo_pagamento_pos_contato,
    (COALESCE(pp.valor_revertido, 0) > 0)  AS houve_reversao,
    -- Referencia: valor que o operador eventualmente digitou (so informativo)
    cc.valor_revertido                     AS valor_revertido_manual_ref
FROM cobranca.cobranca_casos cc
JOIN primeiro_contato pc      ON pc.caso_id     = cc.caso_id      -- so casos COM contato
JOIN unipds.contracts c       ON c.contract_id  = cc.contract_id
JOIN unipds.students  s       ON s.student_id   = c.student_id
JOIN unipds.products  p       ON p.product_id   = c.product_id
JOIN unipds.tenants   t       ON t.tenant_id    = cc.tenant_id
LEFT JOIN pagamentos_pos_contato pp ON pp.caso_id = cc.caso_id;

COMMENT ON VIEW cobranca.vw_reversoes IS
  'Reversao atribuida ao time de contato: casos com >=1 interacao onde o aluno pagou (charges PAGO do mesmo contrato) apos o primeiro contato. Valor bruto, retroativo. Substitui a leitura de reversao via vw_casos_cobranca, que perdia casos ja quitados.';

GRANT SELECT ON cobranca.vw_reversoes TO anon, authenticated, service_role;
