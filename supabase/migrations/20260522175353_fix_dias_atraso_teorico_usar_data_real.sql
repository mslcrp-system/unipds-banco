-- ============================================================
-- Fix vw_cronograma_teorico: dias_atraso_teorico respeita boleto real
--
-- Problema:
--   dias_atraso_teorico usava sempre cr.data_prevista (cronograma
--   matematico vencimento_p1 + (N-1) periodos). Quando a Voomp emite
--   o boleto em data diferente da projetada (ex: P1 venceu 19/03 mas
--   P3 a Voomp emitiu para 26/05 em vez de 19/05), a view reportava
--   atraso indevido enquanto o boleto real ainda nao havia vencido.
--
-- Correcao (alinhada ao modulo cobranca, que so opera VOOMP_EMITIU):
--   - Se a Voomp emitiu boleto (data_vencimento_real IS NOT NULL):
--       atraso conta a partir de data_vencimento_real (verdade Voomp)
--   - Se NAO emitiu (NAO_EMITIDA / data_vencimento_real IS NULL):
--       atraso conta a partir de data_prevista (fragilidade Voomp,
--       captura parcelas que deviam ter sido emitidas)
--
-- Impacto:
--   - Sao mudancas apenas na EXPRESSAO de uma coluna ja existente,
--     mantendo nome, posicao e tipo. CREATE OR REPLACE VIEW suporta.
--   - Nao toca tabelas, nao toca funcoes ETL, nao requer reprocessamento.
--   - Views dependentes (vw_inadimplencia, vw_casos_cobranca,
--     vw_casos_recuperacao) e funcao gerar_casos_inadimplencia
--     passam a refletir o atraso correto automaticamente.
-- ============================================================

CREATE OR REPLACE VIEW unipds.vw_cronograma_teorico AS
WITH p1_paga AS (
    SELECT
        c.contract_id,
        c.data_vencimento AS vencimento_p1
    FROM unipds.charges c
    WHERE c.tipo_cobranca = 'Assinatura'
      AND c.numero_parcela = 1
      AND c.categoria = 'PAGO'
      AND c.contract_id IS NOT NULL
),
contratos_processaveis AS (
    SELECT
        ct.contract_id,
        ct.tenant_id,
        ct.student_id,
        ct.product_id,
        ct.voomp_contrato_id,
        ct.recorrencia_total,
        ct.valor_oferta,
        ct.status_contrato,
        ct.periodo,
        p1.vencimento_p1
    FROM unipds.contracts ct
    JOIN p1_paga p1 ON p1.contract_id = ct.contract_id
    WHERE ct.recorrencia_total IS NOT NULL
      AND ct.recorrencia_total > 0
),
parcelas_teoricas AS (
    SELECT
        cp.*,
        n AS numero_parcela,
        CASE COALESCE(cp.periodo, 'Mensal')
            WHEN 'Mensal'      THEN cp.vencimento_p1 + ((n - 1) * INTERVAL '1 month')
            WHEN 'Semestral'   THEN cp.vencimento_p1 + ((n - 1) * INTERVAL '6 months')
            WHEN 'Anual'       THEN cp.vencimento_p1 + ((n - 1) * INTERVAL '1 year')
            WHEN 'Trimestral'  THEN cp.vencimento_p1 + ((n - 1) * INTERVAL '3 months')
            ELSE                    cp.vencimento_p1 + ((n - 1) * INTERVAL '1 month')
        END::date AS data_prevista
    FROM contratos_processaveis cp
    CROSS JOIN LATERAL generate_series(1, cp.recorrencia_total) AS n
),
com_charge AS (
    SELECT
        pt.*,
        ch.charge_id,
        ch.voomp_venda_id,
        ch.categoria        AS categoria_charge,
        ch.status           AS status_voomp,
        ch.valor_cobrado    AS valor_cobrado_real,
        ch.data_vencimento  AS data_vencimento_real,
        ch.data_pagamento   AS data_pagamento_real,
        ch.dias_atraso      AS dias_atraso_charge
    FROM parcelas_teoricas pt
    LEFT JOIN unipds.charges ch
        ON ch.contract_id    = pt.contract_id
       AND ch.numero_parcela = pt.numero_parcela
),
com_refund AS (
    SELECT
        cc.*,
        r.tipo AS tipo_refund
    FROM com_charge cc
    LEFT JOIN unipds.refunds r ON r.charge_id = cc.charge_id
)
SELECT
    cr.contract_id,
    cr.tenant_id,
    cr.student_id,
    cr.product_id,
    cr.voomp_contrato_id,
    cr.status_contrato,
    cr.numero_parcela,
    cr.recorrencia_total,
    cr.data_prevista,
    cr.valor_oferta AS valor_parcela_previsto,
    CASE
        WHEN cr.tipo_refund = 'Reembolso'      THEN 'REEMBOLSADA'
        WHEN cr.tipo_refund = 'Chargeback'     THEN 'CHARGEBACK'
        WHEN cr.categoria_charge = 'PAGO'      THEN 'PAGA'
        WHEN cr.categoria_charge = 'ABERTO'    THEN 'EM_ABERTO'
        WHEN cr.categoria_charge IS NULL       THEN 'NAO_EMITIDA'
        ELSE 'INDEFINIDA'
    END AS status_parcela,
    cr.charge_id,
    cr.voomp_venda_id,
    cr.valor_cobrado_real,
    cr.data_vencimento_real,
    cr.data_pagamento_real,
    -- Atraso teorico:
    --   - PAGO ou refund: 0
    --   - Voomp emitiu (data_vencimento_real existe): conta desde data_vencimento_real
    --   - Voomp NAO emitiu: conta desde data_prevista (fragilidade)
    CASE
        WHEN cr.tipo_refund IN ('Reembolso','Chargeback')    THEN 0
        WHEN cr.categoria_charge = 'PAGO'                    THEN 0
        WHEN cr.data_vencimento_real IS NOT NULL THEN
             GREATEST((CURRENT_DATE - cr.data_vencimento_real), 0)
        WHEN cr.data_prevista < CURRENT_DATE THEN (CURRENT_DATE - cr.data_prevista)
        ELSE 0
    END AS dias_atraso_teorico,
    cr.dias_atraso_charge
FROM com_refund cr;

COMMENT ON VIEW unipds.vw_cronograma_teorico IS
  'Visao UNIPDS: cronograma teorico por contrato com status real cruzado com charges/refunds. dias_atraso_teorico respeita data_vencimento_real quando Voomp emitiu o boleto; cai para data_prevista apenas em parcelas NAO_EMITIDA (fragilidade Voomp).';
