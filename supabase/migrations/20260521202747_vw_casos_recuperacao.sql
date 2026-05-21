-- ============================================================
-- View cobranca.vw_casos_recuperacao
--
-- Cruzamento LIVE entre processo (cobranca_casos) e
-- verdade financeira (unipds.charges + vw_inadimplencia).
--
-- Para cada caso retorna:
--
--   Tempo do caso (operacional - mede o analista):
--     - dias_caso_aberto         = hoje - data_abertura
--     - dias_desde_ultimo_contato= hoje - data do ultimo contato
--     - duracao_caso_dias        = data_encerramento (ou hoje) - data_abertura
--
--   Verdade financeira (vinda dos charges Voomp):
--     - valor_pago_apos_abertura = soma de charges PAGO pagos
--                                  apos a data_abertura do caso
--     - parcelas_pagas_apos_abertura
--     - data_ultimo_pagamento    = max(data_pagamento) pos-abertura
--     - parcelas_em_aberto_hoje  = count em vw_inadimplencia (live)
--
--   Flags de divergencia/sugestao:
--     - candidato_para_fechar    = analista em (em_aberto|em_contato|em_negociacao)
--                                  AND Voomp ja zerou as parcelas
--                                  -> dashboard sugere fechar
--     - divergencia_analista_pago_voomp_aberto
--                                = analista marcou pago mas
--                                  Voomp ainda mostra parcela aberta
--                                  -> dashboard pede atencao
-- ============================================================

CREATE OR REPLACE VIEW cobranca.vw_casos_recuperacao AS
WITH pagos_apos_abertura AS (
    SELECT
        ch.contract_id,
        SUM(ch.valor_cobrado)   AS valor_pago_apos_abertura,
        COUNT(*)                AS parcelas_pagas_apos_abertura,
        MAX(ch.data_pagamento)  AS data_ultimo_pagamento
    FROM unipds.charges ch
    JOIN cobranca.cobranca_casos cc ON cc.contract_id = ch.contract_id
    WHERE ch.categoria      = 'PAGO'
      AND ch.data_pagamento >= cc.data_abertura
    GROUP BY ch.contract_id
),
inad_atual AS (
    SELECT
        i.contract_id,
        COUNT(*) AS parcelas_em_aberto_hoje
    FROM unipds.vw_inadimplencia i
    WHERE i.situacao_emissao = 'VOOMP_EMITIU'
    GROUP BY i.contract_id
),
ultimo_contato AS (
    SELECT
        ci.caso_id,
        MAX(ci.data_contato) AS data_ultimo_contato_calc
    FROM cobranca.cobranca_interacoes ci
    GROUP BY ci.caso_id
)
SELECT
    cc.caso_id,
    cc.contract_id,
    cc.tenant_id,
    cc.status,
    cc.faixa_aging,
    cc.responsavel,
    cc.data_abertura,
    cc.data_ultima_interacao,
    cc.data_encerramento,

    -- Tempo do caso (operacional / produtividade do analista)
    (CURRENT_DATE - cc.data_abertura)                              AS dias_caso_aberto,
    (CURRENT_DATE - uc.data_ultimo_contato_calc)                   AS dias_desde_ultimo_contato,
    (COALESCE(cc.data_encerramento, CURRENT_DATE) - cc.data_abertura) AS duracao_caso_dias,

    -- Verdade financeira (vinda do Voomp)
    COALESCE(pa.valor_pago_apos_abertura, 0)        AS valor_pago_apos_abertura,
    COALESCE(pa.parcelas_pagas_apos_abertura, 0)    AS parcelas_pagas_apos_abertura,
    pa.data_ultimo_pagamento,
    COALESCE(ia.parcelas_em_aberto_hoje, 0)         AS parcelas_em_aberto_hoje,

    -- Flags de sugestao para o dashboard
    (cc.status IN ('em_aberto','em_contato','em_negociacao')
        AND COALESCE(ia.parcelas_em_aberto_hoje, 0) = 0)
        AS candidato_para_fechar,

    (cc.status = 'pago'
        AND COALESCE(ia.parcelas_em_aberto_hoje, 0) > 0)
        AS divergencia_analista_pago_voomp_aberto

FROM cobranca.cobranca_casos cc
LEFT JOIN pagos_apos_abertura pa ON pa.contract_id = cc.contract_id
LEFT JOIN inad_atual          ia ON ia.contract_id = cc.contract_id
LEFT JOIN ultimo_contato      uc ON uc.caso_id     = cc.caso_id;

COMMENT ON VIEW cobranca.vw_casos_recuperacao IS
  'Cruzamento LIVE de cobranca_casos com charges/vw_inadimplencia. Mede tempo do analista, recuperacao financeira pos-abertura e sinaliza divergencias entre status manual e estado real Voomp.';
