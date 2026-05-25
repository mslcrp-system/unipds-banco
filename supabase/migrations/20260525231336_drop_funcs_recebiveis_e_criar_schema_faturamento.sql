-- ============================================================
-- Drop das 3 funcoes de receita em public + criacao do schema
-- faturamento para isolar a frente de demonstrativo de assinatura.
--
-- As 3 funcoes foram criadas em public por engano em sessao anterior
-- com bugs de calculo (data_prevista em vez de data_vencimento_real,
-- escala bruto/liquido misturada, contratos cancelados inflando
-- pipeline, vendas unicas perdidas). NAO eram consumidas por nenhum
-- front ainda (construcao havia parado quando o erro foi identificado).
--
-- Estrategia: dropar limpo agora e reconstruir corretamente no schema
-- faturamento (migration seguinte). Isolar o dominio evita confusao
-- futura com cobranca/financeiro/unipds.
-- ============================================================

DROP FUNCTION IF EXISTS public.get_recebiveis_mensal(uuid);
DROP FUNCTION IF EXISTS public.get_curva_recebiveis_mensal(uuid);
DROP FUNCTION IF EXISTS public.get_cohort_recebiveis(uuid);

CREATE SCHEMA IF NOT EXISTS faturamento;

GRANT USAGE ON SCHEMA faturamento TO anon, authenticated, service_role;

COMMENT ON SCHEMA faturamento IS
  'Demonstrativo de faturamento de assinatura (escala bruta). Isolado de cobranca/financeiro/unipds. Le dados de unipds.contracts/charges/refunds via view base.';
