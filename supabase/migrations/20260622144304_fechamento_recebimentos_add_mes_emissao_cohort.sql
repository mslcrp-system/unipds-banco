-- ============================================================
-- vw_recebimentos_mensal: + mes_emissao (cohort por safra)
--
-- Permite cruzar mes RECEBIDO (ano_mes) x mes de EMISSAO (safra) e ver
-- quanto do recebimento de um mes veio de vendas de meses anteriores.
--
-- mes_emissao:
--   Assinatura -> data_primeira_venda do contrato (a entrada do aluno)
--   Único      -> proprio mes do pagamento (venda a vista = emissao no mes)
--
-- DROP+CREATE porque ganha coluna (muda grao).
-- ============================================================

DROP VIEW IF EXISTS fechamento.vw_recebimentos_mensal;

CREATE OR REPLACE VIEW fechamento.vw_recebimentos_mensal AS
SELECT
    ch.tenant_id,
    t.nome AS tenant_nome,
    to_char(ch.data_pagamento, 'YYYY-MM') AS ano_mes,
    COALESCE(
        CASE WHEN ch.tipo_cobranca = 'Assinatura'
             THEN to_char(co.data_primeira_venda, 'YYYY-MM') END,
        to_char(ch.data_pagamento, 'YYYY-MM')
    ) AS mes_emissao,
    CASE
        WHEN ch.tipo_cobranca = 'Único'                                  THEN 'Nova'
        WHEN ch.tipo_cobranca = 'Assinatura' AND ch.numero_parcela = 1   THEN 'Nova'
        ELSE 'Recorrente'
    END AS tipo_recebimento,
    pc.classe,
    pc.categoria,
    count(*) AS qtd,
    sum(ch.faturamento_total)                          AS recebido,
    sum(COALESCE(ch.taxa_voomp, 0))                    AS taxa_voomp,
    sum(COALESCE(ch.comissao_coprodutor, 0))           AS taxa_secretaria,
    sum(ch.faturamento_total
        - COALESCE(ch.taxa_voomp, 0)
        - COALESCE(ch.comissao_coprodutor, 0))         AS valor_liquido
FROM unipds.charges ch
JOIN unipds.tenants t                   ON t.tenant_id = ch.tenant_id
JOIN unipds.v_produtos_classificados pc ON pc.product_id = ch.product_id
LEFT JOIN unipds.contracts co           ON co.contract_id = ch.contract_id
WHERE ch.categoria = 'PAGO'
  AND ch.data_pagamento IS NOT NULL
GROUP BY ch.tenant_id, t.nome,
         to_char(ch.data_pagamento, 'YYYY-MM'),
         COALESCE(
             CASE WHEN ch.tipo_cobranca = 'Assinatura'
                  THEN to_char(co.data_primeira_venda, 'YYYY-MM') END,
             to_char(ch.data_pagamento, 'YYYY-MM')
         ),
         CASE
             WHEN ch.tipo_cobranca = 'Único'                                THEN 'Nova'
             WHEN ch.tipo_cobranca = 'Assinatura' AND ch.numero_parcela = 1 THEN 'Nova'
             ELSE 'Recorrente'
         END,
         pc.classe, pc.categoria;

GRANT SELECT ON fechamento.vw_recebimentos_mensal TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
