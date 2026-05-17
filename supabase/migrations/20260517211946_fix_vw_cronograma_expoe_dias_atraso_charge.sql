-- ============================================================
-- Fix vw_cronograma_teorico: expor dias_atraso_charge no SELECT final
--
-- O CTE com_charge calculava ch.dias_atraso AS dias_atraso_charge
-- mas a coluna nao estava no SELECT final da view — logo
-- vw_inadimplencia nao conseguia referencia-la.
--
-- Fix: adicionar cr.dias_atraso_charge ao SELECT final.
-- vw_inadimplencia eh recriada logo abaixo pois depende desta view.
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
    cr.dias_atraso_charge,   -- exposto agora para vw_inadimplencia
    CASE
        WHEN cr.tipo_refund IN ('Reembolso','Chargeback') THEN 0
        WHEN cr.categoria_charge = 'PAGO' THEN 0
        WHEN cr.data_prevista < CURRENT_DATE THEN (CURRENT_DATE - cr.data_prevista)
        ELSE 0
    END AS dias_atraso_teorico
FROM com_refund cr;

COMMENT ON VIEW unipds.vw_cronograma_teorico IS
  'Visao UNIPDS: cronograma teorico por contrato com status real cruzado com charges/refunds. Identifica parcelas NAO_EMITIDAS (fragilidade Voomp).';

-- ============================================================
-- Recriar vw_inadimplencia (depende de vw_cronograma_teorico)
-- ============================================================

CREATE OR REPLACE VIEW unipds.vw_inadimplencia AS
WITH parcelas_devidas AS (
    SELECT
        vt.contract_id,
        vt.tenant_id,
        vt.student_id,
        vt.product_id,
        vt.voomp_contrato_id,
        vt.numero_parcela,
        vt.data_prevista,
        vt.valor_parcela_previsto,
        vt.status_parcela,
        vt.charge_id,
        vt.voomp_venda_id,
        vt.data_vencimento_real,
        vt.dias_atraso_charge AS dias_atraso_voomp,
        vt.dias_atraso_teorico
    FROM unipds.vw_cronograma_teorico vt
    WHERE vt.status_parcela IN ('EM_ABERTO', 'NAO_EMITIDA')
      AND vt.dias_atraso_teorico > 1
)
SELECT
    pd.contract_id,
    pd.tenant_id,
    pd.student_id,
    pd.product_id,
    pd.voomp_contrato_id,
    s.nome              AS aluno_nome,
    s.cpf_cnpj          AS aluno_cpf,
    s.email             AS aluno_email,
    p.nome              AS produto_nome,
    pd.numero_parcela,
    pd.data_prevista,
    pd.data_vencimento_real,
    pd.valor_parcela_previsto,
    pd.status_parcela,
    pd.dias_atraso_voomp,
    pd.dias_atraso_teorico,
    CASE
        WHEN pd.dias_atraso_teorico BETWEEN 2  AND 30  THEN '1_30D'
        WHEN pd.dias_atraso_teorico BETWEEN 31 AND 60  THEN '31_60D'
        WHEN pd.dias_atraso_teorico BETWEEN 61 AND 90  THEN '61_90D'
        WHEN pd.dias_atraso_teorico > 90               THEN '90PLUS'
        ELSE 'EM_DIA'
    END AS bucket_aging,
    CASE
        WHEN pd.status_parcela = 'EM_ABERTO'   THEN 'VOOMP_EMITIU'
        WHEN pd.status_parcela = 'NAO_EMITIDA' THEN 'VOOMP_NAO_EMITIU'
    END AS situacao_emissao
FROM parcelas_devidas pd
JOIN unipds.students s ON s.student_id = pd.student_id
JOIN unipds.products p ON p.product_id = pd.product_id;

COMMENT ON VIEW unipds.vw_inadimplencia IS
  'Inadimplencia consolidada (assinaturas). Atraso > 1 dia. dias_atraso_teorico = Visao Unipds. dias_atraso_voomp = Visao Voomp. situacao_emissao identifica fragilidade 2.';
