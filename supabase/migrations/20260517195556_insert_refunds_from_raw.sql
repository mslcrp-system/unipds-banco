-- ============================================================
-- Funcao insert_refunds_from_raw
--
-- Popula refunds (Reembolso/Chargeback) ligados a charges existentes.
-- Refunds tem FK NOT NULL para charges — so cria se charge existir.
--
-- valor = Valor Pago (o que foi devolvido/contestado)
-- ocorrido_em = COALESCE(Data de pagamento, Data da venda)
-- motivo = NULL (raw nao tem; CHECK aceita NULL)
-- tipo: 'Reembolso' ou 'Chargeback' (Title Case, conforme CHECK constraint)
-- ============================================================

CREATE OR REPLACE FUNCTION unipds.insert_refunds_from_raw(p_modo text DEFAULT 'full')
RETURNS TABLE(inseridos bigint, atualizados bigint)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_inseridos   bigint := 0;
    v_atualizados bigint := 0;
BEGIN
    WITH base AS (
        SELECT
            rl.payload,
            rl.processed_at,
            unipds.classificar_raw_line(rl.payload) AS categoria_raw,
            rl.payload->>'ID Venda'                            AS voomp_venda_id,
            NULLIF(rl.payload->>'Valor Pago', '')::numeric     AS valor,
            COALESCE(
                NULLIF(rl.payload->>'Data de pagamento', '')::timestamptz,
                NULLIF(rl.payload->>'Data da venda', '')::timestamptz
            )                                                  AS ocorrido_em
        FROM unipds.raw_lines rl
        WHERE unipds.classificar_raw_line(rl.payload) IN
              ('CHARGE_REEMBOLSADO','CHARGE_CHARGEBACK')
    ),
    consolidado AS (
        SELECT
            voomp_venda_id,
            (array_remove(array_agg(categoria_raw ORDER BY processed_at DESC), NULL))[1] AS categoria_raw,
            (array_remove(array_agg(valor         ORDER BY processed_at DESC), NULL))[1] AS valor,
            (array_remove(array_agg(ocorrido_em   ORDER BY processed_at DESC), NULL))[1] AS ocorrido_em
        FROM base
        GROUP BY voomp_venda_id
    ),
    enriquecido AS (
        SELECT
            c.voomp_venda_id,
            ch.charge_id,
            CASE c.categoria_raw
                WHEN 'CHARGE_REEMBOLSADO' THEN 'Reembolso'
                WHEN 'CHARGE_CHARGEBACK'  THEN 'Chargeback'
            END AS tipo,
            c.valor,
            c.ocorrido_em
        FROM consolidado c
        JOIN unipds.charges ch ON ch.voomp_venda_id = c.voomp_venda_id
        WHERE c.valor IS NOT NULL
    ),
    upserted AS (
        INSERT INTO unipds.refunds
            (voomp_venda_id, charge_id, tipo, valor, ocorrido_em)
        SELECT voomp_venda_id, charge_id, tipo, valor, ocorrido_em
        FROM enriquecido
        ON CONFLICT (voomp_venda_id) DO UPDATE
        SET charge_id   = EXCLUDED.charge_id,
            tipo        = EXCLUDED.tipo,
            valor       = EXCLUDED.valor,
            ocorrido_em = EXCLUDED.ocorrido_em
        RETURNING (xmax = 0) AS inserted
    )
    SELECT count(*) FILTER (WHERE inserted), count(*) FILTER (WHERE NOT inserted)
    INTO v_inseridos, v_atualizados
    FROM upserted;

    RETURN QUERY SELECT v_inseridos, v_atualizados;
END;
$function$;

COMMENT ON FUNCTION unipds.insert_refunds_from_raw(text) IS
  'Popula refunds (Reembolso/Chargeback) ligados a charges. UPSERT via voomp_venda_id. JOIN obrigatorio com charges existentes.';
