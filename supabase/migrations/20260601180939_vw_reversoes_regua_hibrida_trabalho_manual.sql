-- ============================================================
-- vw_reversoes — REGUA HIBRIDA (substitui a versao so-interacao)
--
-- Motivo: quando o aluno paga, o caso sai da inadimplencia e nao
-- aparece mais na lista ativa — o operador NAO consegue mais abrir
-- o caso para registrar a interacao que faltou. A versao anterior
-- (exigia interacao) descartava casos legitimamente trabalhados pelo
-- time (geraram boleto, conferiram pagamento, falaram com a Voomp)
-- so porque faltou o clique de contato.
--
-- Nova definicao de "caso trabalhado pelo time" (qualquer um basta):
--   - tem >= 1 interacao registrada, OU
--   - status <> 'em_aberto' (operador avancou o caso), OU
--   - valor_revertido preenchido (operador deu baixa), OU
--   - responsavel preenchido (caso foi atribuido)
-- Caso aberto automaticamente e nunca tocado (status em_aberto,
-- sem valor/responsavel/interacao) NAO entra.
--
-- valor_revertido (efetivo):
--   - Corte = COALESCE(primeira_interacao, data_abertura)
--   - Se HA pagamento PAGO detectavel (mesmo contrato) >= corte:
--       usa o valor real pago (bruto). Mantem "digitou 1500, entrou
--       500 -> conta 500".
--   - Se NAO ha pagamento detectavel mas o caso foi trabalhado:
--       usa o valor_revertido manual digitado pelo operador (confia
--       no trabalho do time; casos pre-fix de inadimplencia / baixa
--       conferida fora da nossa base).
--
-- Bruto, retroativo. Dashboard filtra periodo por
-- data_ultimo_pagamento_pos_contato (quando houver pagamento auto).
-- ============================================================

-- Estrutura de colunas mudou (ordem/nomes) — DROP + CREATE
DROP VIEW IF EXISTS cobranca.vw_reversoes;

CREATE VIEW cobranca.vw_reversoes AS
WITH interacoes_agg AS (
    SELECT
        ci.caso_id,
        MIN(ci.data_contato) AS data_primeira_interacao,
        MAX(ci.data_contato) AS data_ultima_interacao,
        COUNT(*)             AS total_interacoes,
        COUNT(*) FILTER (WHERE ci.houve_retorno) AS interacoes_com_retorno
    FROM cobranca.cobranca_interacoes ci
    GROUP BY ci.caso_id
),
-- Casos efetivamente trabalhados pelo time
trabalhados AS (
    SELECT
        cc.caso_id,
        cc.contract_id,
        cc.tenant_id,
        cc.status,
        cc.responsavel,
        cc.data_abertura,
        cc.valor_revertido AS valor_manual,
        ia.data_primeira_interacao,
        ia.data_ultima_interacao,
        COALESCE(ia.total_interacoes, 0)        AS total_interacoes,
        COALESCE(ia.interacoes_com_retorno, 0)  AS interacoes_com_retorno,
        (ia.caso_id IS NOT NULL)                AS tem_interacao,
        COALESCE(ia.data_primeira_interacao, cc.data_abertura) AS corte
    FROM cobranca.cobranca_casos cc
    LEFT JOIN interacoes_agg ia ON ia.caso_id = cc.caso_id
    WHERE ia.caso_id IS NOT NULL          -- tem interacao
       OR cc.status <> 'em_aberto'        -- ou foi avancado
       OR cc.valor_revertido IS NOT NULL  -- ou recebeu baixa manual
       OR cc.responsavel IS NOT NULL      -- ou foi atribuido
),
-- Pagamentos reais detectados apos o inicio do trabalho
pagos AS (
    SELECT
        t.caso_id,
        SUM(ch.valor_cobrado)  AS valor_auto,
        COUNT(*)               AS parcelas_pagas,
        MAX(ch.data_pagamento) AS data_ultimo_pagamento
    FROM trabalhados t
    JOIN unipds.charges ch
        ON ch.contract_id    = t.contract_id
       AND ch.categoria      = 'PAGO'
       AND ch.data_pagamento >= t.corte
    GROUP BY t.caso_id
)
SELECT
    t.caso_id,
    t.contract_id,
    t.tenant_id,
    tn.nome             AS tenant_nome,
    c.voomp_contrato_id,
    s.student_id,
    s.nome              AS aluno_nome,
    s.cpf_cnpj,
    s.email,
    s.telefone,
    p.nome              AS produto_nome,
    t.status            AS status_caso,
    t.responsavel,
    t.data_abertura,
    t.tem_interacao,
    t.total_interacoes,
    t.interacoes_com_retorno,
    t.data_primeira_interacao,
    t.data_ultima_interacao,
    -- valor efetivo: pagamento real se detectado, senao o manual
    CASE WHEN COALESCE(pg.valor_auto, 0) > 0
         THEN pg.valor_auto
         ELSE COALESCE(t.valor_manual, 0)
    END AS valor_revertido,
    -- origem do valor, para auditoria/transparencia no dashboard
    CASE WHEN COALESCE(pg.valor_auto, 0) > 0 THEN 'pagamento_detectado'
         WHEN COALESCE(t.valor_manual, 0) > 0 THEN 'baixa_manual'
         ELSE 'sem_reversao'
    END AS origem_valor,
    COALESCE(pg.parcelas_pagas, 0)        AS parcelas_pagas_pos_corte,
    pg.data_ultimo_pagamento             AS data_ultimo_pagamento_pos_contato,
    t.valor_manual                        AS valor_revertido_manual_ref,
    COALESCE(pg.valor_auto, 0)            AS valor_pago_detectado,
    (CASE WHEN COALESCE(pg.valor_auto, 0) > 0 THEN pg.valor_auto
          ELSE COALESCE(t.valor_manual, 0) END > 0) AS houve_reversao
FROM trabalhados t
JOIN unipds.contracts c  ON c.contract_id  = t.contract_id
JOIN unipds.students  s  ON s.student_id   = c.student_id
JOIN unipds.products  p  ON p.product_id   = c.product_id
JOIN unipds.tenants   tn ON tn.tenant_id   = t.tenant_id
LEFT JOIN pagos pg ON pg.caso_id = t.caso_id;

COMMENT ON VIEW cobranca.vw_reversoes IS
  'Reversao do time (regua hibrida): caso trabalhado = interacao OU status avancado OU valor/responsavel preenchido. valor_revertido = pagamento real pos-corte se detectado, senao o valor manual digitado. origem_valor indica qual foi usado. Bruto, retroativo.';

GRANT SELECT ON cobranca.vw_reversoes TO anon, authenticated, service_role;
