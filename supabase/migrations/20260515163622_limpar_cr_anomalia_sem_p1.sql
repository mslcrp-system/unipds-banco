-- ============================================================
-- LIMPEZA DO CR: anomalia 'contrato sem P1 paga'
--
-- Objetivo: tirar do CR (previsao_parcelas) as ~750 parcelas de
-- 84 contratos de assinatura canonica que tem previsao gerada
-- mas nao tem P1 paga. Esses contratos nao sao 'clientes' pela
-- definicao oficial e estavam inflando CR e inadimplencia.
--
-- Etapas:
--  1. Mover 79 contratos novos para casos_anomalia (5 ja estavam la)
--  2. Marcar todas as parcelas previsto/vencido desses 84 como
--     'cancelado' em previsao_parcelas
-- ============================================================

-- ETAPA 1: Inserir os 79 contratos orfaos em casos_anomalia
-- (os 5 ja estao la desde a Fase 5 e nao sao reinseridos)
INSERT INTO cobranca.casos_anomalia (
    caso_id,
    tenant_id,
    contract_id,
    valor_total_aberto,
    parcelas_vencidas,
    faixa_aging,
    data_abertura,
    tipo_anomalia,
    observacao
)
SELECT
    gen_random_uuid(),
    c.tenant_id,
    c.contract_id,
    COALESCE(SUM(pp.valor_previsto) FILTER (WHERE pp.status IN ('previsto','vencido')), 0),
    COUNT(*) FILTER (WHERE pp.status = 'vencido')::integer,
    CASE
        WHEN MAX(CURRENT_DATE - pp.data_prevista) FILTER (WHERE pp.status='vencido') IS NULL
            THEN 'faixa_1'::cobranca.faixa_aging
        WHEN MAX(CURRENT_DATE - pp.data_prevista) FILTER (WHERE pp.status='vencido') <= 30
            THEN 'faixa_1'::cobranca.faixa_aging
        WHEN MAX(CURRENT_DATE - pp.data_prevista) FILTER (WHERE pp.status='vencido') <= 60
            THEN 'faixa_2'::cobranca.faixa_aging
        WHEN MAX(CURRENT_DATE - pp.data_prevista) FILTER (WHERE pp.status='vencido') <= 90
            THEN 'faixa_3'::cobranca.faixa_aging
        ELSE 'faixa_4'::cobranca.faixa_aging
    END,
    now(),
    'sem_p1',
    'Detectado em auditoria de CR 15/05/2026 - contrato com previsao gerada mas sem P1 paga. Limpeza automatica do CR.'
FROM unipds.contracts c
JOIN unipds.previsao_parcelas pp ON pp.contract_id = c.contract_id
WHERE pp.status IN ('previsto','vencido')
  AND NOT EXISTS (
    SELECT 1 FROM unipds.charges ch
    WHERE ch.contract_id = c.contract_id
      AND ch.numero_parcela = 1
      AND ch.status = 'Pago'
      AND ch.valor_cobrado > 0
  )
  AND NOT EXISTS (
    SELECT 1 FROM cobranca.casos_anomalia ca
    WHERE ca.contract_id = c.contract_id
  )
GROUP BY c.tenant_id, c.contract_id;

-- ETAPA 2: Marcar como 'cancelado' todas as parcelas previsto/vencido
-- dos 84 contratos sem P1 paga (inclui os 5 que ja estavam em quarentena)
UPDATE unipds.previsao_parcelas pp
SET status = 'cancelado',
    updated_at = now()
WHERE pp.status IN ('previsto','vencido')
  AND NOT EXISTS (
    SELECT 1 FROM unipds.charges ch
    WHERE ch.contract_id = pp.contract_id
      AND ch.numero_parcela = 1
      AND ch.status = 'Pago'
      AND ch.valor_cobrado > 0
  );

-- ============================================================
-- Resultado esperado (validar pos db push):
-- - casos_anomalia passa de 5 para 84 registros
-- - Aproximadamente 750 parcelas mudam de previsto/vencido para cancelado
-- - CR (v_contas_a_receber) cai em ~R$ 546.800
-- - Inadimplencia (v_inadimplencia) cai proporcionalmente
-- ============================================================
