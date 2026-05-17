-- ============================================================
-- Atualizacao: 'Erro no processamento' tratado como tentativa recusada
--
-- Encontrados 3 raw_lines com Status da venda = 'Erro no processamento'
-- (eventos abortados pela Voomp antes de chegar a status final).
-- Conceitualmente equivalente a Recusado: nao houve pagamento.
-- ============================================================

CREATE OR REPLACE FUNCTION unipds.classificar_raw_line(p_payload jsonb)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT CASE p_payload->>'Status da venda'
    WHEN 'Pago'                  THEN 'CHARGE_PAGO'
    WHEN 'Aguardando Pagamento'  THEN 'CHARGE_ABERTO'
    WHEN 'Reembolsado'           THEN 'CHARGE_REEMBOLSADO'
    WHEN 'Reembolso Pendente'    THEN 'CHARGE_REEMBOLSADO'
    WHEN 'Chargeback'            THEN 'CHARGE_CHARGEBACK'
    WHEN 'Recusado'              THEN 'TENTATIVA_RECUSADA'
    WHEN 'failed'                THEN 'TENTATIVA_RECUSADA'
    WHEN 'Erro no processamento' THEN 'TENTATIVA_RECUSADA'
    ELSE 'DESCONHECIDO'
  END;
$function$;
