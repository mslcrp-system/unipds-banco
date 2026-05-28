-- ============================================================
-- View faturamento.vw_contratos_risco_cancelamento
--
-- Detecta contratos com padrao de "cancelamento de fato" — alunos
-- que pararam de pagar mas a Voomp ainda nao marcou
-- status_contrato = 'Cancelado'. Sinaliza valor em risco no CR.
--
-- Filtra: status_contrato <> 'Cancelado' (so casos nao declarados)
-- Inclui: apenas contratos com pelo menos 1 parcela inadimplente
--
-- Score de risco:
--   ALTO   - 3+ parcelas vencidas + 90+ dias sem pagamento
--   MEDIO  - 2+ parcelas vencidas + 60+ dias sem pagamento
--   BAIXO  - 1 parcela vencida (inadimplencia normal, nao risco)
--
-- valor_em_risco = parcelas EM_ABERTO vencidas + NAO_EMITIDA
--   (tudo que ainda esta no CR mas pode nunca ser pago)
--
-- Uso esperado:
--   - KPI "Valor em risco — possivel cancelamento nao declarado"
--   - Lista filtrada por score=ALTO para revisao manual
-- ============================================================

CREATE OR REPLACE VIEW faturamento.vw_contratos_risco_cancelamento AS
WITH parcelas AS (
    SELECT
        vpc.contract_id,
        vpc.tenant_id,
        vpc.voomp_contrato_id,
        vpc.status_contrato,
        vpc.recorrencia_total,
        vpc.numero_parcela,
        vpc.status_parcela,
        vpc.data_referencia,
        vpc.data_pagamento,
        vpc.valor_previsto
    FROM faturamento.vw_parcelas_contratuais vpc
    WHERE vpc.status_contrato <> 'Cancelado'  -- apenas nao declarados
),
metricas_contrato AS (
    SELECT
        contract_id,
        tenant_id,
        voomp_contrato_id,
        status_contrato,
        recorrencia_total,
        COUNT(*) FILTER (WHERE status_parcela = 'PAGA')                     AS parcelas_pagas,
        COUNT(*) FILTER (WHERE status_parcela = 'EM_ABERTO'
                          AND data_referencia < CURRENT_DATE)                AS parcelas_vencidas_em_aberto,
        COUNT(*) FILTER (WHERE status_parcela = 'NAO_EMITIDA')              AS parcelas_nao_emitidas,
        MAX(data_pagamento)                                                  AS ultimo_pagamento,
        MIN(data_referencia) FILTER (WHERE status_parcela = 'EM_ABERTO'
                                      AND data_referencia < CURRENT_DATE)   AS data_primeira_inadimplencia,
        SUM(CASE
              WHEN status_parcela = 'EM_ABERTO' AND data_referencia < CURRENT_DATE THEN valor_previsto
              WHEN status_parcela = 'NAO_EMITIDA'                                  THEN valor_previsto
              ELSE 0
            END)                                                             AS valor_em_risco,
        SUM(CASE
              WHEN status_parcela = 'EM_ABERTO' AND data_referencia < CURRENT_DATE THEN valor_previsto
              ELSE 0
            END)                                                             AS valor_vencido_aberto,
        SUM(CASE
              WHEN status_parcela = 'NAO_EMITIDA'                            THEN valor_previsto
              ELSE 0
            END)                                                             AS valor_nao_emitido
    FROM parcelas
    GROUP BY contract_id, tenant_id, voomp_contrato_id, status_contrato, recorrencia_total
)
SELECT
    mc.contract_id,
    mc.tenant_id,
    t.nome                                                              AS tenant_nome,
    mc.voomp_contrato_id,
    s.student_id,
    s.nome                                                              AS aluno_nome,
    s.cpf_cnpj,
    s.email,
    s.telefone,
    p.nome                                                              AS produto_nome,
    mc.status_contrato,
    mc.recorrencia_total,
    mc.parcelas_pagas,
    mc.parcelas_vencidas_em_aberto,
    mc.parcelas_nao_emitidas,
    mc.ultimo_pagamento,
    mc.data_primeira_inadimplencia,
    CASE
        WHEN mc.ultimo_pagamento IS NULL THEN NULL
        ELSE (CURRENT_DATE - mc.ultimo_pagamento)
    END                                                                 AS dias_desde_ultimo_pagamento,
    CASE
        WHEN mc.data_primeira_inadimplencia IS NULL THEN NULL
        ELSE (CURRENT_DATE - mc.data_primeira_inadimplencia)
    END                                                                 AS dias_em_inadimplencia,
    mc.valor_vencido_aberto,
    mc.valor_nao_emitido,
    mc.valor_em_risco,
    -- Score
    CASE
        WHEN mc.parcelas_vencidas_em_aberto >= 3
         AND (CURRENT_DATE - COALESCE(mc.ultimo_pagamento,
                                       mc.data_primeira_inadimplencia)) >= 90
        THEN 'ALTO'
        WHEN mc.parcelas_vencidas_em_aberto >= 2
         AND (CURRENT_DATE - COALESCE(mc.ultimo_pagamento,
                                       mc.data_primeira_inadimplencia)) >= 60
        THEN 'MEDIO'
        ELSE 'BAIXO'
    END                                                                 AS score_risco
FROM metricas_contrato mc
JOIN unipds.contracts c ON c.contract_id = mc.contract_id
JOIN unipds.students  s ON s.student_id  = c.student_id
JOIN unipds.tenants   t ON t.tenant_id   = mc.tenant_id
JOIN unipds.products  p ON p.product_id  = c.product_id
WHERE mc.parcelas_vencidas_em_aberto > 0;  -- so quem ja tem inadimplencia

GRANT SELECT ON faturamento.vw_contratos_risco_cancelamento TO anon, authenticated, service_role;

COMMENT ON VIEW faturamento.vw_contratos_risco_cancelamento IS
  'Contratos com padrao de cancelamento de fato (alunos que pararam de pagar) mas que a Voomp nao marcou Cancelado. Sinaliza valor_em_risco no CR e classifica em score ALTO/MEDIO/BAIXO. Apenas contratos com pelo menos 1 parcela inadimplente.';
