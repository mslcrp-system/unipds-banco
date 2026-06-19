-- ============================================================
-- fechamento: parametros fiscais + lucratividade gerencial
--
-- Fecha o objetivo final: receita -> liquido -> impostos -> lucro,
-- no mesmo modelo bookings/TCV (reconhece na entrada, reverte na saida).
--
-- VALOR LIQUIDO (base dos impostos) = Faturamento - Taxa Voomp - Taxa
-- Secretaria. Voomp e co-produtor sao SPLIT de pagamento que NAO chega
-- na Unipds, logo nao sao tributados (definicao do dono, 19/06/2026).
--
-- IMPOSTOS (% sobre o liquido, iguais p/ os dois tenants):
--   ISS 5% | PIS 0,65% | COFINS 3% | IRPJ presumido 8% | CSLL presumido 2,88%
-- Guardados em tabela VERSIONADA (vigencia) no banco -> fechamento
-- reproduzivel/auditavel. Financeiro edita os valores via migration/SQL.
--
-- LINEARIDADE: tudo escala por parcela x quantidade, entao a reversao de
-- churn/reembolso reduz faturamento E taxas, e impostos/lucro revertem
-- proporcionalmente. Reconhecido acumulado = realizado.
-- ============================================================

-- ------------------------------------------------------------
-- Parametros fiscais (versionados; tenant_id NULL = vale p/ todos)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS fechamento.parametros_fiscais (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    imposto         text NOT NULL,
    aliquota        numeric NOT NULL,          -- fracao (0.05 = 5%)
    base            text NOT NULL DEFAULT 'LIQUIDO',
    tenant_id       uuid REFERENCES unipds.tenants(tenant_id),  -- NULL = global
    vigencia_inicio date NOT NULL,
    vigencia_fim    date,                       -- NULL = vigente
    descricao       text,
    created_at      timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON fechamento.parametros_fiscais TO anon, authenticated, service_role;

INSERT INTO fechamento.parametros_fiscais (imposto, aliquota, base, tenant_id, vigencia_inicio, descricao)
VALUES
    ('ISS',    0.0500, 'LIQUIDO', NULL, '2026-01-01', 'ISS 5%'),
    ('PIS',    0.0065, 'LIQUIDO', NULL, '2026-01-01', 'PIS 0,65%'),
    ('COFINS', 0.0300, 'LIQUIDO', NULL, '2026-01-01', 'COFINS 3%'),
    ('IRPJ',   0.0800, 'LIQUIDO', NULL, '2026-01-01', 'IRPJ presumido 8%'),
    ('CSLL',   0.0288, 'LIQUIDO', NULL, '2026-01-01', 'CSLL presumido 2,88%');

-- ------------------------------------------------------------
-- Eventos: agora carregam tambem taxa_voomp e taxa_secretaria
-- (mesmo sinal/escala do faturamento, p/ a reversao funcionar)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW fechamento.vw_faturamento_eventos AS
WITH p1 AS (
    SELECT ch.contract_id,
           ch.tenant_id,
           ch.faturamento_total              AS valor_parcela,
           COALESCE(ch.taxa_voomp, 0)        AS taxa_voomp_parcela,
           COALESCE(ch.comissao_coprodutor,0) AS taxa_secret_parcela,
           ch.data_pagamento::date           AS data_p1
    FROM unipds.charges ch
    WHERE ch.tipo_cobranca = 'Assinatura'
      AND ch.numero_parcela = 1
      AND ch.data_pagamento IS NOT NULL
      AND ch.contract_id IS NOT NULL
),
pagas AS (
    SELECT contract_id, count(*) AS qtd_pagas
    FROM unipds.charges
    WHERE tipo_cobranca = 'Assinatura' AND status = 'Pago'
    GROUP BY contract_id
),
churn_proxy AS (
    SELECT contract_id,
           COALESCE(
               min(data_vencimento) FILTER (WHERE status <> 'Pago' AND data_vencimento IS NOT NULL),
               max(data_pagamento::date) FILTER (WHERE status = 'Pago')
           ) AS data_churn
    FROM unipds.charges
    WHERE tipo_cobranca = 'Assinatura'
    GROUP BY contract_id
)
-- LEG 1: BOOKING ASSINATURA
SELECT p1.tenant_id, p1.contract_id, NULL::text AS voomp_venda_id,
       'BOOKING_ASSINATURA'::text AS evento,
       p1.data_p1 AS competencia, to_char(p1.data_p1, 'YYYY-MM') AS ano_mes,
       (p1.valor_parcela       * COALESCE(NULLIF(c.recorrencia_total,0),1)) AS valor,
       (p1.taxa_voomp_parcela  * COALESCE(NULLIF(c.recorrencia_total,0),1)) AS taxa_voomp,
       (p1.taxa_secret_parcela * COALESCE(NULLIF(c.recorrencia_total,0),1)) AS taxa_secretaria
FROM p1 JOIN unipds.contracts c ON c.contract_id = p1.contract_id

UNION ALL
-- LEG 2: BOOKING A VISTA
SELECT ch.tenant_id, NULL::uuid, ch.voomp_venda_id,
       'BOOKING_AVISTA'::text,
       ch.data_pagamento::date, to_char(ch.data_pagamento, 'YYYY-MM'),
       ch.faturamento_total,
       COALESCE(ch.taxa_voomp, 0),
       COALESCE(ch.comissao_coprodutor, 0)
FROM unipds.charges ch
WHERE ch.tipo_cobranca = 'Único' AND ch.data_pagamento IS NOT NULL

UNION ALL
-- LEG 3: REVERSAO REEMBOLSO/CB (a vista)
SELECT ch.tenant_id, NULL::uuid, ch.voomp_venda_id,
       'REVERSAO_REEMBOLSO_AVISTA'::text,
       COALESCE(r.ocorrido_em::date, ch.data_pagamento::date),
       to_char(COALESCE(r.ocorrido_em, ch.data_pagamento::timestamptz), 'YYYY-MM'),
       -ch.faturamento_total,
       -COALESCE(ch.taxa_voomp, 0),
       -COALESCE(ch.comissao_coprodutor, 0)
FROM unipds.charges ch
LEFT JOIN unipds.refunds r ON r.voomp_venda_id = ch.voomp_venda_id
WHERE ch.tipo_cobranca = 'Único' AND ch.categoria IN ('REEMBOLSADO','CHARGEBACK')

UNION ALL
-- LEG 4: REVERSAO CHURN (assinatura) — reverte o restante nao realizado
SELECT c.tenant_id, c.contract_id, NULL::text,
       'REVERSAO_CHURN_ASSINATURA'::text,
       cp.data_churn, to_char(cp.data_churn::timestamptz, 'YYYY-MM'),
       -((COALESCE(NULLIF(c.recorrencia_total,0),1) - COALESCE(pg.qtd_pagas,0)) * p1.valor_parcela),
       -((COALESCE(NULLIF(c.recorrencia_total,0),1) - COALESCE(pg.qtd_pagas,0)) * p1.taxa_voomp_parcela),
       -((COALESCE(NULLIF(c.recorrencia_total,0),1) - COALESCE(pg.qtd_pagas,0)) * p1.taxa_secret_parcela)
FROM unipds.contracts c
JOIN p1 ON p1.contract_id = c.contract_id
LEFT JOIN pagas pg       ON pg.contract_id = c.contract_id
LEFT JOIN churn_proxy cp ON cp.contract_id = c.contract_id
WHERE c.tipo_cobranca = 'Assinatura'
  AND c.status_contrato IN ('Cancelado','Encerrado','Reembolsado')
  AND (COALESCE(NULLIF(c.recorrencia_total,0),1) - COALESCE(pg.qtd_pagas,0)) > 0;

GRANT SELECT ON fechamento.vw_faturamento_eventos TO anon, authenticated, service_role;

-- ------------------------------------------------------------
-- Lucratividade mensal (o demonstrativo que o dash consome)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW fechamento.vw_lucratividade_mensal AS
WITH ev AS (
    SELECT tenant_id, ano_mes,
           sum(valor)           AS faturamento_bruto,
           sum(taxa_voomp)      AS taxa_voomp,
           sum(taxa_secretaria) AS taxa_secretaria
    FROM fechamento.vw_faturamento_eventos
    GROUP BY tenant_id, ano_mes
),
liq AS (
    SELECT ev.*, (faturamento_bruto - taxa_voomp - taxa_secretaria) AS valor_liquido
    FROM ev
),
aliq AS (  -- aliquotas vigentes em cada competencia (global)
    SELECT d.ano_mes,
           COALESCE(sum(p.aliquota) FILTER (WHERE p.imposto='ISS'),    0) AS iss,
           COALESCE(sum(p.aliquota) FILTER (WHERE p.imposto='PIS'),    0) AS pis,
           COALESCE(sum(p.aliquota) FILTER (WHERE p.imposto='COFINS'), 0) AS cofins,
           COALESCE(sum(p.aliquota) FILTER (WHERE p.imposto='IRPJ'),   0) AS irpj,
           COALESCE(sum(p.aliquota) FILTER (WHERE p.imposto='CSLL'),   0) AS csll
    FROM (SELECT DISTINCT ano_mes FROM liq) d
    LEFT JOIN fechamento.parametros_fiscais p
           ON to_date(d.ano_mes||'-01','YYYY-MM-DD') >= p.vigencia_inicio
          AND (p.vigencia_fim IS NULL OR to_date(d.ano_mes||'-01','YYYY-MM-DD') <= p.vigencia_fim)
          AND p.tenant_id IS NULL
    GROUP BY d.ano_mes
)
SELECT l.tenant_id,
       t.nome AS tenant_nome,
       l.ano_mes,
       l.faturamento_bruto,
       l.taxa_voomp,
       l.taxa_secretaria,
       l.valor_liquido,
       round(l.valor_liquido * a.iss,    2) AS iss,
       round(l.valor_liquido * a.pis,    2) AS pis,
       round(l.valor_liquido * a.cofins, 2) AS cofins,
       round(l.valor_liquido * a.irpj,   2) AS irpj,
       round(l.valor_liquido * a.csll,   2) AS csll,
       round(l.valor_liquido * (a.iss+a.pis+a.cofins+a.irpj+a.csll), 2) AS total_impostos,
       round(l.valor_liquido * (1 - (a.iss+a.pis+a.cofins+a.irpj+a.csll)), 2) AS lucratividade
FROM liq l
JOIN aliq a USING (ano_mes)
JOIN unipds.tenants t ON t.tenant_id = l.tenant_id;

GRANT SELECT ON fechamento.vw_lucratividade_mensal TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
