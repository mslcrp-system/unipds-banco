-- ============================================================
-- Schema fechamento: faturamento gerencial (modelo bookings/TCV)
--
-- Schema NOVO, separado de:
--   - faturamento  -> validacao comercial x fiscal (acao manual)
--   - conciliacao  -> Pipe (CRM) x Voomp (mes fechado)
--
-- MODELO (definido pelo dono, 19/06/2026):
--   - Competencia = data de pagamento.
--   - Assinatura: ao pagar a P1, reconhece o CONTRATO INTEIRO (TCV)
--     no mes do pagamento da P1. TCV = faturamento_total(P1) x recorrencia.
--   - A vista (Único): valor cheio (faturamento_total) no mes do pagamento.
--   - Reembolso: reverte no mes do estorno (proxy = data_pagamento;
--     ver ressalva abaixo).
--   - Churn: contrato reconhecido cheio na entrada; ao SAIR
--     (status_contrato Cancelado/Encerrado/Reembolsado) reverte o
--     RESTANTE nao realizado = (recorrencia - parcelas_pagas) x parcela.
--     Logica contabil autocorretiva: reconhecido acumulado = realizado.
--
-- BASE DE VALOR: charges.faturamento_total (valor real, sem juros,
-- pos-cupom; reembolso/CB ja reconstruido no ETL).
--
-- RESSALVAS (documentadas, olhar o dado):
--   - "Não pago" NAO e churn (e inadimplencia, ex. Caio) -> gatilho de
--     churn so em Cancelado/Encerrado/Reembolsado.
--   - data_encerramento esta 100% vazia -> proxy da data de saida =
--     vencimento da 1a parcela NAO paga (fallback: ultimo pagamento).
--   - data do estorno NAO existe no export de vendas (a Data de
--     pagamento e o pagamento original) -> proxy = data_pagamento.
--     Exato p/ reembolso no mesmo mes; cross-mes exige ingerir o extrato.
--   - Reembolso de parcela isolada em assinatura ATIVA (sem cancelar) nao
--     e revertido no v1 (raro; o churn reverte no encerramento).
--
-- Consumo: o repo de fechamento le destas views (NAO de unipds.charges).
-- ============================================================

CREATE SCHEMA IF NOT EXISTS fechamento;
GRANT USAGE ON SCHEMA fechamento TO anon, authenticated, service_role;

-- ------------------------------------------------------------
-- Eventos de faturamento (grao: 1 linha por evento contabil)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW fechamento.vw_faturamento_eventos AS
WITH p1 AS (  -- P1 paga de cada assinatura (unidade do TCV)
    SELECT ch.contract_id,
           ch.tenant_id,
           ch.faturamento_total           AS valor_parcela,
           ch.data_pagamento::date        AS data_p1
    FROM unipds.charges ch
    WHERE ch.tipo_cobranca = 'Assinatura'
      AND ch.numero_parcela = 1
      AND ch.data_pagamento IS NOT NULL
      AND ch.contract_id IS NOT NULL
),
pagas AS (  -- parcelas efetivamente pagas por contrato
    SELECT contract_id, count(*) AS qtd_pagas
    FROM unipds.charges
    WHERE tipo_cobranca = 'Assinatura' AND status = 'Pago'
    GROUP BY contract_id
),
churn_proxy AS (  -- data de saida = 1o vencimento nao pago (fallback: ultimo pgto)
    SELECT contract_id,
           COALESCE(
               min(data_vencimento) FILTER (WHERE status <> 'Pago' AND data_vencimento IS NOT NULL),
               max(data_pagamento::date) FILTER (WHERE status = 'Pago')
           ) AS data_churn
    FROM unipds.charges
    WHERE tipo_cobranca = 'Assinatura'
    GROUP BY contract_id
)
-- LEG 1: BOOKING ASSINATURA (TCV cheio no mes da P1)
SELECT p1.tenant_id,
       p1.contract_id,
       NULL::text                                         AS voomp_venda_id,
       'BOOKING_ASSINATURA'::text                         AS evento,
       p1.data_p1                                         AS competencia,
       to_char(p1.data_p1, 'YYYY-MM')                     AS ano_mes,
       (p1.valor_parcela * COALESCE(NULLIF(c.recorrencia_total,0),1)) AS valor
FROM p1
JOIN unipds.contracts c ON c.contract_id = p1.contract_id

UNION ALL
-- LEG 2: BOOKING A VISTA (valor cheio no mes do pagamento)
SELECT ch.tenant_id,
       NULL::uuid,
       ch.voomp_venda_id,
       'BOOKING_AVISTA'::text,
       ch.data_pagamento::date,
       to_char(ch.data_pagamento, 'YYYY-MM'),
       ch.faturamento_total
FROM unipds.charges ch
WHERE ch.tipo_cobranca = 'Único'
  AND ch.data_pagamento IS NOT NULL

UNION ALL
-- LEG 3: REVERSAO REEMBOLSO/CB (a vista) no mes do estorno (proxy)
SELECT ch.tenant_id,
       NULL::uuid,
       ch.voomp_venda_id,
       'REVERSAO_REEMBOLSO_AVISTA'::text,
       COALESCE(r.ocorrido_em::date, ch.data_pagamento::date),
       to_char(COALESCE(r.ocorrido_em, ch.data_pagamento::timestamptz), 'YYYY-MM'),
       -ch.faturamento_total
FROM unipds.charges ch
LEFT JOIN unipds.refunds r ON r.voomp_venda_id = ch.voomp_venda_id
WHERE ch.tipo_cobranca = 'Único'
  AND ch.categoria IN ('REEMBOLSADO','CHARGEBACK')

UNION ALL
-- LEG 4: REVERSAO CHURN (assinatura) — reverte o restante nao realizado
SELECT c.tenant_id,
       c.contract_id,
       NULL::text,
       'REVERSAO_CHURN_ASSINATURA'::text,
       cp.data_churn,
       to_char(cp.data_churn::timestamptz, 'YYYY-MM'),
       -((COALESCE(NULLIF(c.recorrencia_total,0),1) - COALESCE(pg.qtd_pagas,0)) * p1.valor_parcela)
FROM unipds.contracts c
JOIN p1               ON p1.contract_id = c.contract_id
LEFT JOIN pagas pg    ON pg.contract_id = c.contract_id
LEFT JOIN churn_proxy cp ON cp.contract_id = c.contract_id
WHERE c.tipo_cobranca = 'Assinatura'
  AND c.status_contrato IN ('Cancelado','Encerrado','Reembolsado')
  AND (COALESCE(NULLIF(c.recorrencia_total,0),1) - COALESCE(pg.qtd_pagas,0)) > 0;

GRANT SELECT ON fechamento.vw_faturamento_eventos TO anon, authenticated, service_role;

-- ------------------------------------------------------------
-- Resumo mensal (o que o dash consome direto)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW fechamento.vw_faturamento_mensal AS
SELECT e.tenant_id,
       t.nome AS tenant_nome,
       e.ano_mes,
       sum(e.valor) FILTER (WHERE e.evento = 'BOOKING_ASSINATURA')        AS booking_assinatura,
       sum(e.valor) FILTER (WHERE e.evento = 'BOOKING_AVISTA')            AS booking_avista,
       sum(e.valor) FILTER (WHERE e.evento LIKE 'BOOKING%')               AS faturamento_bruto,
       sum(e.valor) FILTER (WHERE e.evento = 'REVERSAO_REEMBOLSO_AVISTA') AS reversao_reembolso,
       sum(e.valor) FILTER (WHERE e.evento = 'REVERSAO_CHURN_ASSINATURA') AS reversao_churn,
       sum(e.valor)                                                        AS faturamento_liquido
FROM fechamento.vw_faturamento_eventos e
JOIN unipds.tenants t ON t.tenant_id = e.tenant_id
GROUP BY e.tenant_id, t.nome, e.ano_mes;

GRANT SELECT ON fechamento.vw_faturamento_mensal TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
