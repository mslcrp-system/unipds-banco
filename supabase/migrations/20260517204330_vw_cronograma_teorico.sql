-- ============================================================
-- View vw_cronograma_teorico
--
-- Materializa o CRONOGRAMA CONTRATUAL TEORICO de cada contrato
-- de assinatura. Uma linha por parcela teorica (1 a recorrencia_total).
--
-- Visao UNIPDS: o que deveriamos ter cobrado segundo o contrato.
-- Usada para confrontar com charges reais e identificar fragilidades
-- da Voomp (parcelas que ela nao emitiu).
--
-- Calculo data_prevista (caminho B):
--   - Pega data_vencimento da P1 paga real
--   - Adiciona (N-1) periodos
--   - Atualmente todos contratos = Mensal
--
-- Status real de cada parcela cruzando com charges/refunds:
--   - 'PAGA' - charge PAGO existe
--   - 'EM_ABERTO' - charge ABERTO existe
--   - 'REEMBOLSADA' - refund Reembolso associado
--   - 'CHARGEBACK' - refund Chargeback associado
--   - 'NAO_EMITIDA' - nenhum charge para essa parcela (Voomp atrasou)
--
-- Pre-requisitos:
--   - Contrato deve ter recorrencia_total preenchido
--   - Contrato deve ter P1 paga (para vencimento_p1)
-- ============================================================

CREATE OR REPLACE VIEW unipds.vw_cronograma_teorico AS
WITH p1_paga AS (
    -- Pega a data_vencimento da P1 paga de cada contrato
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
    -- Contratos elegiveis para expansao
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
    -- Expande N linhas por contrato (1 a recorrencia_total)
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
    -- LEFT JOIN com a charge real (se existir)
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
    -- LEFT JOIN com refund (se a charge teve reembolso/chargeback)
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
    -- Status normalizado da parcela
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
    -- dias_atraso TEORICO (Visao Unipds): conta atraso desde data_prevista
    CASE
        WHEN cr.tipo_refund IN ('Reembolso','Chargeback') THEN 0
        WHEN cr.categoria_charge = 'PAGO' THEN 0
        WHEN cr.data_prevista < CURRENT_DATE THEN (CURRENT_DATE - cr.data_prevista)
        ELSE 0
    END AS dias_atraso_teorico
FROM com_refund cr;

COMMENT ON VIEW unipds.vw_cronograma_teorico IS
  'Visao UNIPDS: cronograma teorico por contrato com status real cruzado com charges/refunds. Identifica parcelas NAO_EMITIDAS (fragilidade Voomp).';
