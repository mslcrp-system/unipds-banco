-- ============================================================
-- Dimensao `categoria` (linha do demonstrativo) — abre o ADMINISTRATIVO
-- em Multa / Cancelamento / Negociação.
--
-- `classe` (POS_GRADUACAO/EXTENSAO/ADMINISTRATIVO) continua para a logica
-- fiscal (so curso e tributado). `categoria` e a quebra fina que o repo
-- de fechamento usa pra abrir as linhas:
--   Pós-Graduação · Extensão · Multa · Cancelamento · Negociação
--
-- Mapa ADMINISTRATIVO -> categoria:
--   9752, 11972, 12228, 12229  -> Multa
--   15428                       -> Cancelamento
--   10908                       -> Negociação
-- (curso ainda distingue Multa Pós × Multa Extensão no drill-down.)
-- ============================================================

CREATE OR REPLACE VIEW unipds.v_produtos_classificados AS
SELECT q.product_id,
       q.voomp_produto_id,
       q.nome,
       q.tipo,
       q.classe,
       CASE
           WHEN q.classe = 'POS_GRADUACAO' AND q.nome ILIKE '%Java Elite%'  THEN 'Pós-Graduação Java Elite'
           WHEN q.classe = 'POS_GRADUACAO' AND q.nome ILIKE '%IA Aplicada%' THEN 'Pós-Graduação Engenharia de IA Aplicada'
           WHEN q.classe = 'EXTENSAO'      AND q.nome ILIKE '%Java Elite%'  THEN 'Extensão Universitária Java Elite'
           WHEN q.classe = 'EXTENSAO'      AND q.nome ILIKE '%IA Aplicada%' THEN 'Extensão Engenharia de IA Aplicada'
           WHEN q.classe = 'ADMINISTRATIVO' THEN trim(regexp_replace(q.nome, '\s*-\s*vlr único\s*$', '', 'i'))
           ELSE q.nome
       END AS curso,
       CASE
           WHEN q.classe = 'POS_GRADUACAO' THEN 'Pós-Graduação'
           WHEN q.classe = 'EXTENSAO'      THEN 'Extensão'
           WHEN q.voomp_produto_id = ANY (ARRAY['9752','11972','12228','12229']) THEN 'Multa'
           WHEN q.voomp_produto_id = '15428' THEN 'Cancelamento'
           WHEN q.voomp_produto_id = '10908' THEN 'Negociação'
           ELSE 'Outro'
       END AS categoria
FROM (
    SELECT product_id, voomp_produto_id, nome, tipo,
        CASE
            WHEN voomp_produto_id = ANY (ARRAY['7724','7852','13761','13762','12663']) THEN 'POS_GRADUACAO'
            WHEN voomp_produto_id = ANY (ARRAY['7725','7856']) THEN 'EXTENSAO'
            WHEN voomp_produto_id = ANY (ARRAY['9752','12228','10908']) THEN 'ADMINISTRATIVO'
            WHEN voomp_produto_id = ANY (ARRAY['11957','11971','12657','12658','12882','13459','13764','13766']) THEN 'POS_GRADUACAO'
            WHEN voomp_produto_id = ANY (ARRAY['11973','11974','13497','14164','14165','14168']) THEN 'EXTENSAO'
            WHEN voomp_produto_id = ANY (ARRAY['11972','12229','15428']) THEN 'ADMINISTRATIVO'
            ELSE 'OUTRO'
        END AS classe
    FROM unipds.products
) q;

GRANT SELECT ON unipds.v_produtos_classificados TO anon, authenticated, service_role;

-- ------------------------------------------------------------
-- Views do fechamento: + categoria (DROP porque muda estrutura/grao)
-- ------------------------------------------------------------
DROP VIEW IF EXISTS fechamento.vw_lucratividade_mensal;
DROP VIEW IF EXISTS fechamento.vw_faturamento_mensal;
DROP VIEW IF EXISTS fechamento.vw_faturamento_eventos;

CREATE OR REPLACE VIEW fechamento.vw_faturamento_eventos AS
WITH p1 AS (
    SELECT ch.contract_id, ch.tenant_id,
           ch.faturamento_total               AS valor_parcela,
           COALESCE(ch.taxa_voomp, 0)         AS taxa_voomp_parcela,
           COALESCE(ch.comissao_coprodutor,0) AS taxa_secret_parcela,
           ch.data_pagamento::date            AS data_p1
    FROM unipds.charges ch
    WHERE ch.tipo_cobranca = 'Assinatura' AND ch.numero_parcela = 1
      AND ch.data_pagamento IS NOT NULL AND ch.contract_id IS NOT NULL
),
pagas AS (
    SELECT contract_id, count(*) AS qtd_pagas
    FROM unipds.charges WHERE tipo_cobranca = 'Assinatura' AND status = 'Pago'
    GROUP BY contract_id
),
churn_proxy AS (
    SELECT contract_id,
           COALESCE(
               min(data_vencimento) FILTER (WHERE status <> 'Pago' AND data_vencimento IS NOT NULL),
               max(data_pagamento::date) FILTER (WHERE status = 'Pago')
           ) AS data_churn
    FROM unipds.charges WHERE tipo_cobranca = 'Assinatura'
    GROUP BY contract_id
)
SELECT p1.tenant_id, p1.contract_id, NULL::text AS voomp_venda_id,
       c.product_id, pc.curso, pc.classe, pc.categoria,
       'BOOKING_ASSINATURA'::text AS evento,
       p1.data_p1 AS competencia, to_char(p1.data_p1, 'YYYY-MM') AS ano_mes,
       (p1.valor_parcela       * COALESCE(NULLIF(c.recorrencia_total,0),1)) AS valor,
       (p1.taxa_voomp_parcela  * COALESCE(NULLIF(c.recorrencia_total,0),1)) AS taxa_voomp,
       (p1.taxa_secret_parcela * COALESCE(NULLIF(c.recorrencia_total,0),1)) AS taxa_secretaria
FROM p1
JOIN unipds.contracts c               ON c.contract_id = p1.contract_id
JOIN unipds.v_produtos_classificados pc ON pc.product_id = c.product_id

UNION ALL
SELECT ch.tenant_id, NULL::uuid, ch.voomp_venda_id,
       ch.product_id, pc.curso, pc.classe, pc.categoria,
       'BOOKING_AVISTA'::text,
       ch.data_pagamento::date, to_char(ch.data_pagamento, 'YYYY-MM'),
       ch.faturamento_total, COALESCE(ch.taxa_voomp,0), COALESCE(ch.comissao_coprodutor,0)
FROM unipds.charges ch
JOIN unipds.v_produtos_classificados pc ON pc.product_id = ch.product_id
WHERE ch.tipo_cobranca = 'Único' AND ch.data_pagamento IS NOT NULL

UNION ALL
SELECT ch.tenant_id, NULL::uuid, ch.voomp_venda_id,
       ch.product_id, pc.curso, pc.classe, pc.categoria,
       'REVERSAO_REEMBOLSO_AVISTA'::text,
       COALESCE(r.ocorrido_em::date, ch.data_pagamento::date),
       to_char(COALESCE(r.ocorrido_em, ch.data_pagamento::timestamptz), 'YYYY-MM'),
       -ch.faturamento_total, -COALESCE(ch.taxa_voomp,0), -COALESCE(ch.comissao_coprodutor,0)
FROM unipds.charges ch
LEFT JOIN unipds.refunds r              ON r.voomp_venda_id = ch.voomp_venda_id
JOIN unipds.v_produtos_classificados pc ON pc.product_id = ch.product_id
WHERE ch.tipo_cobranca = 'Único' AND ch.categoria IN ('REEMBOLSADO','CHARGEBACK')

UNION ALL
SELECT c.tenant_id, c.contract_id, NULL::text,
       c.product_id, pc.curso, pc.classe, pc.categoria,
       'REVERSAO_CHURN_ASSINATURA'::text,
       cp.data_churn, to_char(cp.data_churn::timestamptz, 'YYYY-MM'),
       -((COALESCE(NULLIF(c.recorrencia_total,0),1) - COALESCE(pg.qtd_pagas,0)) * p1.valor_parcela),
       -((COALESCE(NULLIF(c.recorrencia_total,0),1) - COALESCE(pg.qtd_pagas,0)) * p1.taxa_voomp_parcela),
       -((COALESCE(NULLIF(c.recorrencia_total,0),1) - COALESCE(pg.qtd_pagas,0)) * p1.taxa_secret_parcela)
FROM unipds.contracts c
JOIN p1                                 ON p1.contract_id = c.contract_id
JOIN unipds.v_produtos_classificados pc ON pc.product_id = c.product_id
LEFT JOIN pagas pg                      ON pg.contract_id = c.contract_id
LEFT JOIN churn_proxy cp                ON cp.contract_id = c.contract_id
WHERE c.tipo_cobranca = 'Assinatura'
  AND c.status_contrato IN ('Cancelado','Encerrado','Reembolsado')
  AND (COALESCE(NULLIF(c.recorrencia_total,0),1) - COALESCE(pg.qtd_pagas,0)) > 0;

GRANT SELECT ON fechamento.vw_faturamento_eventos TO anon, authenticated, service_role;

-- Resumo mensal por categoria (carrega classe junto — 1:1 dentro da categoria)
CREATE OR REPLACE VIEW fechamento.vw_faturamento_mensal AS
SELECT e.tenant_id, t.nome AS tenant_nome, e.ano_mes, e.classe, e.categoria,
       sum(e.valor) FILTER (WHERE e.evento = 'BOOKING_ASSINATURA')        AS booking_assinatura,
       sum(e.valor) FILTER (WHERE e.evento = 'BOOKING_AVISTA')            AS booking_avista,
       sum(e.valor) FILTER (WHERE e.evento LIKE 'BOOKING%')               AS faturamento_bruto,
       sum(e.valor) FILTER (WHERE e.evento = 'REVERSAO_REEMBOLSO_AVISTA') AS reversao_reembolso,
       sum(e.valor) FILTER (WHERE e.evento = 'REVERSAO_CHURN_ASSINATURA') AS reversao_churn,
       sum(e.valor)                                                        AS faturamento_liquido
FROM fechamento.vw_faturamento_eventos e
JOIN unipds.tenants t ON t.tenant_id = e.tenant_id
GROUP BY e.tenant_id, t.nome, e.ano_mes, e.classe, e.categoria;

GRANT SELECT ON fechamento.vw_faturamento_mensal TO anon, authenticated, service_role;

-- Lucratividade mensal por categoria (imposto de servico so em curso)
CREATE OR REPLACE VIEW fechamento.vw_lucratividade_mensal AS
WITH ev AS (
    SELECT tenant_id, ano_mes, classe, categoria,
           sum(valor)           AS faturamento_bruto,
           sum(taxa_voomp)      AS taxa_voomp,
           sum(taxa_secretaria) AS taxa_secretaria
    FROM fechamento.vw_faturamento_eventos
    GROUP BY tenant_id, ano_mes, classe, categoria
),
liq AS (
    SELECT ev.*, (faturamento_bruto - taxa_voomp - taxa_secretaria) AS valor_liquido FROM ev
),
aliq AS (
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
),
calc AS (
    SELECT l.*, (l.classe IN ('POS_GRADUACAO','EXTENSAO'))::int AS tributa,
           a.iss, a.pis, a.cofins, a.irpj, a.csll
    FROM liq l JOIN aliq a USING (ano_mes)
)
SELECT c.tenant_id, t.nome AS tenant_nome, c.ano_mes, c.classe, c.categoria,
       c.faturamento_bruto, c.taxa_voomp, c.taxa_secretaria, c.valor_liquido,
       round(c.valor_liquido * c.iss    * c.tributa, 2) AS iss,
       round(c.valor_liquido * c.pis    * c.tributa, 2) AS pis,
       round(c.valor_liquido * c.cofins * c.tributa, 2) AS cofins,
       round(c.valor_liquido * c.irpj   * c.tributa, 2) AS irpj,
       round(c.valor_liquido * c.csll   * c.tributa, 2) AS csll,
       round(c.valor_liquido * (c.iss+c.pis+c.cofins+c.irpj+c.csll) * c.tributa, 2) AS total_impostos,
       round(c.valor_liquido * (1 - (c.iss+c.pis+c.cofins+c.irpj+c.csll) * c.tributa), 2) AS lucratividade
FROM calc c
JOIN unipds.tenants t ON t.tenant_id = c.tenant_id;

GRANT SELECT ON fechamento.vw_lucratividade_mensal TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
