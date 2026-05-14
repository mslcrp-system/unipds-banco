CREATE OR REPLACE FUNCTION unipds.gerar_previsoes_pendentes()
RETURNS integer
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
    v_contract_id   uuid;
    v_processados   integer := 0;
BEGIN
    FOR v_contract_id IN
        SELECT c.contract_id
        FROM unipds.contracts c
        WHERE c.tipo_cobranca      = 'Assinatura'
          AND c.contrato_canonico  = TRUE
          AND EXISTS (
              SELECT 1
              FROM unipds.charges ch
              WHERE ch.contract_id    = c.contract_id
                AND ch.numero_parcela = 1
                AND ch.status         = 'Pago'
                AND ch.valor_cobrado  > 0
          )
          AND NOT EXISTS (
              SELECT 1
              FROM unipds.previsao_parcelas pp
              WHERE pp.contract_id = c.contract_id
          )
    LOOP
        PERFORM unipds.gerar_previsao_parcelas(v_contract_id);
        v_processados := v_processados + 1;
    END LOOP;

    RETURN v_processados;
END;
$$;

COMMENT ON FUNCTION unipds.gerar_previsoes_pendentes() IS
    'Gera previsão de parcelas para contratos de assinatura canônicos com P1 paga que ainda não têm nenhuma linha em previsao_parcelas.';
