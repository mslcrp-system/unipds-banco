-- ============================================================
-- Performance Comercial (automatica) — captados, evasao, base, churn.
--
-- Regua AUTOMATICA definida pelo banco (nao ancorada no book manual):
--   Captado  = aluno na 1a compra paga (data = primeira matricula paga).
--   Evadido  = refund/CB  OU  contrato Cancelado/Encerrado/Reembolsado
--              OU  inadimplente parado ha >= 90 dias (linha de churn).
--   data_evasao = a mais antiga entre: data do refund; vencimento da 1a
--                 parcela nao paga (cancelamento); vencimento da parcela
--                 vencida (inadimplencia). Guard: evasao >= captacao.
--   Base(fim M) = captados ate M menos evadidos ate M (liquida, as-of).
--   Churn(M)    = evadidos(M) / base(inicio M).
--
-- 90 dias e default de mentor (controladoria pode mudar -> migration).
-- ============================================================

CREATE OR REPLACE VIEW fechamento.vw_comercial_aluno AS
WITH cap AS (  -- captacao: 1a compra paga por aluno
    SELECT m.student_id, m.tenant_id,
           min(m.data_matricula) AS data_captacao,
           (array_agg(m.tipo_curso ORDER BY m.data_matricula))[1] AS classe,
           (array_agg(m.modalidade ORDER BY m.data_matricula))[1] AS modalidade
    FROM unipds.v_matriculas_ativas m
    GROUP BY m.student_id, m.tenant_id
),
ref AS (  -- evasao por refund/chargeback
    SELECT c.student_id, min(r.ocorrido_em::date) AS dt
    FROM unipds.charges c JOIN unipds.refunds r ON r.charge_id = c.charge_id
    GROUP BY c.student_id
),
canc AS (  -- evasao por contrato cancelado (proxy: 1o venc nao pago / ult pgto)
    SELECT ct.student_id, min(cp.dt) AS dt
    FROM unipds.contracts ct
    JOIN LATERAL (
        SELECT COALESCE(
                   min(vpc.data_referencia) FILTER (WHERE vpc.status_parcela <> 'PAGA'),
                   max(vpc.data_pagamento)  FILTER (WHERE vpc.status_parcela =  'PAGA')
               ) AS dt
        FROM faturamento.vw_parcelas_contratuais vpc
        WHERE vpc.contract_id = ct.contract_id
    ) cp ON true
    WHERE ct.status_contrato IN ('Cancelado','Encerrado','Reembolsado')
    GROUP BY ct.student_id
),
inad AS (  -- evasao por inadimplencia >= 90 dias
    SELECT ct.student_id, min(vpc.data_referencia) AS dt
    FROM faturamento.vw_parcelas_contratuais vpc
    JOIN unipds.contracts ct ON ct.contract_id = vpc.contract_id
    WHERE vpc.status_parcela = 'EM_ABERTO'
      AND vpc.data_referencia < (CURRENT_DATE - 90)
    GROUP BY ct.student_id
),
ev AS (  -- evasao consolidada: data mais antiga + motivo
    SELECT student_id, min(dt) AS data_evasao,
           (array_agg(motivo ORDER BY dt))[1] AS motivo
    FROM (
        SELECT student_id, dt, 'Refund'::text        AS motivo FROM ref  WHERE dt IS NOT NULL
        UNION ALL
        SELECT student_id, dt, 'Cancelamento'::text  FROM canc WHERE dt IS NOT NULL
        UNION ALL
        SELECT student_id, dt, 'Inadimplencia'::text FROM inad WHERE dt IS NOT NULL
    ) u
    GROUP BY student_id
)
SELECT cap.student_id, cap.tenant_id, cap.classe, cap.modalidade,
       cap.data_captacao,
       CASE WHEN ev.data_evasao >= cap.data_captacao THEN ev.data_evasao END AS data_evasao,
       CASE WHEN ev.data_evasao >= cap.data_captacao THEN ev.motivo     END AS motivo_evasao
FROM cap
LEFT JOIN ev ON ev.student_id = cap.student_id;

GRANT SELECT ON fechamento.vw_comercial_aluno TO anon, authenticated, service_role;

-- ------------------------------------------------------------
-- Serie mensal: captados, evadidos, base, churn por tenant
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW fechamento.vw_performance_comercial_mensal AS
WITH a AS (SELECT * FROM fechamento.vw_comercial_aluno),
meses AS (
    SELECT generate_series(
               date_trunc('month', (SELECT min(data_captacao) FROM a)),
               date_trunc('month', CURRENT_DATE),
               interval '1 month')::date AS mi
),
mt AS (
    SELECT m.mi, t.tenant_id, t.nome AS tenant_nome
    FROM meses m CROSS JOIN unipds.tenants t
),
base AS (
    SELECT to_char(mt.mi,'YYYY-MM') AS ano_mes, mt.mi, mt.tenant_id, mt.tenant_nome,
        count(a.student_id) FILTER (WHERE date_trunc('month', a.data_captacao) = mt.mi) AS captados,
        count(a.student_id) FILTER (WHERE date_trunc('month', a.data_evasao)   = mt.mi) AS evadidos,
        count(a.student_id) FILTER (WHERE a.data_captacao < (mt.mi + interval '1 month')
                                     AND (a.data_evasao IS NULL OR a.data_evasao >= (mt.mi + interval '1 month'))) AS base_fim
    FROM mt
    LEFT JOIN a ON a.tenant_id = mt.tenant_id
    GROUP BY mt.mi, mt.tenant_id, mt.tenant_nome
)
SELECT ano_mes, tenant_id, tenant_nome, captados, evadidos, base_fim,
       lag(base_fim) OVER (PARTITION BY tenant_id ORDER BY mi) AS base_inicio,
       ROUND(100.0 * evadidos / NULLIF(lag(base_fim) OVER (PARTITION BY tenant_id ORDER BY mi), 0), 2) AS churn_pct
FROM base
ORDER BY mi, tenant_nome;

GRANT SELECT ON fechamento.vw_performance_comercial_mensal TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
