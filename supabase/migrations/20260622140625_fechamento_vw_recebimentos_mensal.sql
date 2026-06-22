-- ============================================================
-- fechamento.vw_recebimentos_mensal — recebido (caixa) por mes,
-- quebrado em Nova venda x Recorrente (pro fluxo de caixa).
--
-- Diferente do faturamento gerencial (bookings/TCV): aqui e CAIXA —
-- so o que foi efetivamente RECEBIDO (charges PAGO), por data_pagamento.
--
-- Regua de valor = faturamento_total (valor real sem juros, mesma do
-- faturamento gerencial). E o BRUTO real (antes de Voomp/co-produtor);
-- o liquido sai tirando taxa_voomp + taxa_secretaria (colunas inclusas).
--
-- tipo_recebimento:
--   Nova       = a vista (Único) + entrada da assinatura (parcela 1)
--   Recorrente = parcelas 2..N da assinatura
--
-- Convencao "recebido" = charges.categoria 'PAGO' (mesma da CR e do
-- cohort). Reembolso/CB nao entram aqui (sao saida/despesa, tratados
-- a parte). Competencia = data_pagamento.
-- ============================================================

CREATE OR REPLACE VIEW fechamento.vw_recebimentos_mensal AS
SELECT
    ch.tenant_id,
    t.nome AS tenant_nome,
    to_char(ch.data_pagamento, 'YYYY-MM') AS ano_mes,
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
WHERE ch.categoria = 'PAGO'
  AND ch.data_pagamento IS NOT NULL
GROUP BY ch.tenant_id, t.nome,
         to_char(ch.data_pagamento, 'YYYY-MM'),
         CASE
             WHEN ch.tipo_cobranca = 'Único'                                THEN 'Nova'
             WHEN ch.tipo_cobranca = 'Assinatura' AND ch.numero_parcela = 1 THEN 'Nova'
             ELSE 'Recorrente'
         END,
         pc.classe, pc.categoria;

GRANT SELECT ON fechamento.vw_recebimentos_mensal TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
