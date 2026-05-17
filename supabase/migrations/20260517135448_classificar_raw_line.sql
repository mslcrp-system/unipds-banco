-- ============================================================
-- classificar_raw_line
--
-- Função pura (IMMUTABLE) que recebe um payload JSONB de uma
-- linha do raw Voomp e retorna a categoria de classificação
-- usada pelo ETL de ingestão.
--
-- Categorias:
--   CHARGE_PAGO           - parcela paga com sucesso
--   CHARGE_ABERTO         - aguardando pagamento
--   CHARGE_REEMBOLSADO    - reembolso concluído ou pendente
--   CHARGE_CHARGEBACK     - chargeback
--   TENTATIVA_RECUSADA    - pagamento recusado ou falhou
--   DESCONHECIDO          - status não mapeado
-- ============================================================

CREATE OR REPLACE FUNCTION unipds.classificar_raw_line(p_payload jsonb)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT CASE p_payload->>'Status da venda'
    WHEN 'Pago'                 THEN 'CHARGE_PAGO'
    WHEN 'Aguardando Pagamento' THEN 'CHARGE_ABERTO'
    WHEN 'Reembolsado'          THEN 'CHARGE_REEMBOLSADO'
    WHEN 'Reembolso Pendente'   THEN 'CHARGE_REEMBOLSADO'
    WHEN 'Chargeback'           THEN 'CHARGE_CHARGEBACK'
    WHEN 'Recusado'             THEN 'TENTATIVA_RECUSADA'
    WHEN 'failed'               THEN 'TENTATIVA_RECUSADA'
    ELSE 'DESCONHECIDO'
  END;
$function$;

COMMENT ON FUNCTION unipds.classificar_raw_line(jsonb) IS
  'Classifica uma linha do raw Voomp em uma das 5 categorias do ETL (Pago/Aberto/Reembolsado/Chargeback/Recusada) ou DESCONHECIDO. Funcao pura, IMMUTABLE.';
