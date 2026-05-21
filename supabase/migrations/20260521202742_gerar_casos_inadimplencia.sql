-- ============================================================
-- Funcao cobranca.gerar_casos_inadimplencia
--
-- Lê unipds.vw_inadimplencia e cria casos novos em cobranca_casos
-- para contratos inadimplentes que ainda nao tem caso aberto.
--
-- Regras:
--   - Apenas situacao_emissao = 'VOOMP_EMITIU' (mesma logica de
--     vw_casos_cobranca; parcelas NAO_EMITIDA sao fragilidade Voomp
--     e ainda nao foram efetivamente cobradas)
--   - Agrupa por contract_id (1 caso por contrato)
--   - data_abertura = CURRENT_DATE (data em que o analista passou
--     a conhecer o caso). O atraso real continua disponivel em
--     vw_inadimplencia.max_dias_atraso
--   - status inicial = 'em_aberto'
--   - faixa_aging = a pior faixa entre as parcelas vencidas do contrato
--   - valor_total_aberto = SUM(valor_parcela_previsto)
--   - parcelas_vencidas = COUNT(*) das parcelas
--
-- CRITICO: ON CONFLICT (contract_id) DO NOTHING
--   Nunca toca em casos existentes (status manual do analista
--   permanece intacto). Roda quantas vezes quiser - idempotente.
--
-- Retorna apenas o count de casos novos inseridos.
-- ============================================================

CREATE OR REPLACE FUNCTION cobranca.gerar_casos_inadimplencia()
RETURNS TABLE(inseridos bigint)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_inseridos bigint := 0;
BEGIN
    WITH casos_candidatos AS (
        SELECT
            i.contract_id,
            i.tenant_id,
            -- Pega o pior bucket entre as parcelas vencidas do contrato
            -- 90PLUS > 61_90D > 31_60D > 1_30D
            CASE MAX(
                CASE i.bucket_aging
                    WHEN '90PLUS' THEN 4
                    WHEN '61_90D' THEN 3
                    WHEN '31_60D' THEN 2
                    WHEN '1_30D'  THEN 1
                    ELSE 0
                END
            )
                WHEN 4 THEN 'faixa_4'
                WHEN 3 THEN 'faixa_3'
                WHEN 2 THEN 'faixa_2'
                ELSE       'faixa_1'
            END AS faixa_aging,
            COUNT(*)                       AS parcelas_vencidas,
            SUM(i.valor_parcela_previsto)  AS valor_total_aberto
        FROM unipds.vw_inadimplencia i
        WHERE i.situacao_emissao = 'VOOMP_EMITIU'
        GROUP BY i.contract_id, i.tenant_id
    ),
    novos AS (
        INSERT INTO cobranca.cobranca_casos
            (contract_id, tenant_id, status, faixa_aging,
             valor_total_aberto, parcelas_vencidas, data_abertura)
        SELECT
            contract_id, tenant_id, 'em_aberto', faixa_aging,
            valor_total_aberto, parcelas_vencidas, CURRENT_DATE
        FROM casos_candidatos
        ON CONFLICT (contract_id) DO NOTHING
        RETURNING caso_id
    )
    SELECT count(*) INTO v_inseridos FROM novos;

    RETURN QUERY SELECT v_inseridos;
END;
$function$;

COMMENT ON FUNCTION cobranca.gerar_casos_inadimplencia() IS
  'Cria casos novos em cobranca_casos a partir de unipds.vw_inadimplencia. Idempotente via ON CONFLICT DO NOTHING. NUNCA atualiza casos existentes - status manual do analista permanece intocado.';
