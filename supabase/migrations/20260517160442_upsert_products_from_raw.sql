-- ============================================================
-- Funcao upsert_products_from_raw
--
-- Consolida raw_lines em unipds.products, preservando UUIDs
-- existentes via chave natural (tenant_id, voomp_produto_id).
--
-- Politicas (paralelas a upsert_students_from_raw):
--   - Ultimo valor nao-nulo por campo (ORDER BY processed_at DESC)
--   - Sem normalizacao complexa (nomes mantidos como vieram)
--   - Produto sem ID Produto valido => raw_lines_skipped (PRODUTO_INVALIDO)
--
-- Retorna: (inseridos, atualizados, skipped)
-- ============================================================

CREATE OR REPLACE FUNCTION unipds.upsert_products_from_raw(p_modo text DEFAULT 'full')
RETURNS TABLE(inseridos bigint, atualizados bigint, skipped bigint)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_inseridos   bigint := 0;
    v_atualizados bigint := 0;
    v_skipped     bigint := 0;
BEGIN
    -- ETAPA 1: Linhas com ID Produto invalido -> inbox
    WITH inserted_skip AS (
        INSERT INTO unipds.raw_lines_skipped
            (line_id, import_id, payload, motivo_skip, status_raw)
        SELECT
            rl.line_id, rl.import_id, rl.payload, 'PRODUTO_INVALIDO',
            rl.payload->>'Status da venda'
        FROM unipds.raw_lines rl
        WHERE NULLIF(trim(rl.payload->>'ID Produto'), '') IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM unipds.raw_lines_skipped s
              WHERE s.line_id = rl.line_id AND s.motivo_skip = 'PRODUTO_INVALIDO'
          )
        RETURNING skip_id
    )
    SELECT count(*) INTO v_skipped FROM inserted_skip;

    -- ETAPA 2: Consolidar por (tenant_id, voomp_produto_id)
    WITH raw_validas AS (
        SELECT
            f.tenant_id,
            trim(rl.payload->>'ID Produto')                  AS voomp_produto_id,
            NULLIF(trim(rl.payload->>'Nome do produto'), '')  AS nome,
            NULLIF(trim(rl.payload->>'Tipo do produto'), '')  AS tipo,
            NULLIF(trim(rl.payload->>'Categoria'), '')        AS categoria,
            rl.processed_at
        FROM unipds.raw_lines rl
        JOIN unipds.raw_imports ri ON ri.import_id = rl.import_id
        JOIN unipds.fontes f       ON f.fonte_id = ri.fonte_id
        WHERE NULLIF(trim(rl.payload->>'ID Produto'), '') IS NOT NULL
    ),
    consolidado AS (
        SELECT
            tenant_id,
            voomp_produto_id,
            (array_remove(array_agg(nome      ORDER BY processed_at DESC), NULL))[1] AS nome,
            (array_remove(array_agg(tipo      ORDER BY processed_at DESC), NULL))[1] AS tipo,
            (array_remove(array_agg(categoria ORDER BY processed_at DESC), NULL))[1] AS categoria
        FROM raw_validas
        GROUP BY tenant_id, voomp_produto_id
    ),
    upserted AS (
        INSERT INTO unipds.products (tenant_id, voomp_produto_id, nome, tipo, categoria, ativo)
        SELECT tenant_id, voomp_produto_id, nome, tipo, categoria, true
        FROM consolidado
        ON CONFLICT (tenant_id, voomp_produto_id) DO UPDATE
        SET
            nome       = EXCLUDED.nome,
            tipo       = EXCLUDED.tipo,
            categoria  = EXCLUDED.categoria,
            updated_at = now()
        RETURNING (xmax = 0) AS inserted
    )
    SELECT
        count(*) FILTER (WHERE inserted),
        count(*) FILTER (WHERE NOT inserted)
    INTO v_inseridos, v_atualizados
    FROM upserted;

    RETURN QUERY SELECT v_inseridos, v_atualizados, v_skipped;
END;
$function$;

COMMENT ON FUNCTION unipds.upsert_products_from_raw(text) IS
  'Consolida raw_lines em products via UNIQUE(tenant_id, voomp_produto_id). Ultimo valor nao-nulo por campo. ID Produto invalido vai para raw_lines_skipped.';
