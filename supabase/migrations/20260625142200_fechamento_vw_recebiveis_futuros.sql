-- ============================================================
-- fechamento.vw_recebiveis_futuros — projecao da recorrencia a receber
-- por mes de vencimento futuro (runway das assinaturas).
--
-- Mostra, do mes corrente em diante, quanto de recebivel cada tenant
-- ainda tem agendado (parcelas NAO pagas das assinaturas), em
-- faturamento_total. Serve pra ver "ate onde Java sobrevive" — a curva
-- decai conforme os contratos completam as 12 parcelas.
--
-- Base: vw_recebiveis_parcela (assinatura-only; a vista nao tem
-- recebivel futuro). Parcela "a receber" = nao paga e nao reembolsada.
-- ============================================================

CREATE OR REPLACE VIEW fechamento.vw_recebiveis_futuros AS
SELECT
    r.tenant_id,
    t.nome AS tenant_nome,
    to_char(r.data_referencia, 'YYYY-MM') AS mes_vencimento,
    r.classe,
    count(DISTINCT r.contract_id) AS qtd_contratos,
    count(*)                      AS qtd_parcelas,
    sum(r.valor)                  AS a_receber
FROM fechamento.vw_recebiveis_parcela r
JOIN unipds.tenants t ON t.tenant_id = r.tenant_id
WHERE r.data_pagamento IS NULL
  AND r.status_parcela NOT IN ('REEMBOLSADA','CHARGEBACK')
  AND r.data_referencia >= date_trunc('month', CURRENT_DATE)::date
GROUP BY r.tenant_id, t.nome, to_char(r.data_referencia, 'YYYY-MM'), r.classe;

GRANT SELECT ON fechamento.vw_recebiveis_futuros TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
