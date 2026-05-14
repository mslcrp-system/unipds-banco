CREATE OR REPLACE FUNCTION unipds.recalcular_previsao_vencida()
RETURNS integer
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
    v_rows integer;
BEGIN
    UPDATE unipds.previsao_parcelas
    SET status = 'vencido'
    WHERE status = 'previsto'
      AND charge_id IS NULL
      AND data_prevista < CURRENT_DATE;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows;
END;
$$;

COMMENT ON FUNCTION unipds.recalcular_previsao_vencida() IS
    'Reavalia parcelas previstas que já passaram do vencimento: muda status de previsto para vencido onde charge_id IS NULL e data_prevista < CURRENT_DATE.';
