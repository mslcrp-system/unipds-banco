CREATE OR REPLACE FUNCTION cobranca.gerar_casos_inadimplencia()
RETURNS integer
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
    v_total integer := 0;
BEGIN
    WITH inadimplentes AS (
        SELECT
            c.contract_id,
            vi.tenant_id,
            COUNT(*)                              AS parcelas_vencidas,
            SUM(vi.valor_devido)                  AS valor_total_aberto,
            CASE
                WHEN MAX(vi.dias_atraso) <= 30  THEN 'faixa_1'::cobranca.faixa_aging
                WHEN MAX(vi.dias_atraso) <= 60  THEN 'faixa_2'::cobranca.faixa_aging
                WHEN MAX(vi.dias_atraso) <= 90  THEN 'faixa_3'::cobranca.faixa_aging
                ELSE                                 'faixa_4'::cobranca.faixa_aging
            END                                   AS faixa_aging
        FROM unipds.v_inadimplencia vi
        JOIN unipds.contracts c ON c.contract_ref = vi.contract_ref
                               AND c.tenant_id    = vi.tenant_id
        GROUP BY c.contract_id, vi.tenant_id
    )
    INSERT INTO cobranca.cobranca_casos (
        contract_id,
        tenant_id,
        status,
        faixa_aging,
        valor_total_aberto,
        parcelas_vencidas,
        data_abertura,
        updated_at
    )
    SELECT
        contract_id,
        tenant_id,
        'em_aberto'::cobranca.status_caso,
        faixa_aging,
        valor_total_aberto,
        parcelas_vencidas,
        now(),
        now()
    FROM inadimplentes
    ON CONFLICT (contract_id) DO UPDATE
        SET faixa_aging        = EXCLUDED.faixa_aging,
            valor_total_aberto = EXCLUDED.valor_total_aberto,
            parcelas_vencidas  = EXCLUDED.parcelas_vencidas,
            updated_at         = now();

    GET DIAGNOSTICS v_total = ROW_COUNT;
    RETURN v_total;
END;
$$;

COMMENT ON FUNCTION cobranca.gerar_casos_inadimplencia() IS
    'Popula cobranca.cobranca_casos a partir de unipds.v_inadimplencia: cria casos novos com status em_aberto ou atualiza faixa_aging, valor_total_aberto, parcelas_vencidas e updated_at em casos existentes. Não altera status, data_abertura, responsavel nem nenhuma outra coluna operacional.';
