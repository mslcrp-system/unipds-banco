-- ============================================================
-- Funcao upsert_contracts_from_raw
--
-- Terceira sub-funcao do ETL novo. Consolida raw_lines em
-- unipds.contracts SOMENTE para assinaturas (vendas unicas
-- nao geram contrato, vao direto para charges em 2g).
--
-- Regua de inclusao:
--   - Tipo de cobranca = 'Assinatura'
--   - ID Contrato preenchido
--   - JOIN sucesso com students (cpf_cnpj valido)
--   - JOIN sucesso com products (voomp_produto_id valido)
--
-- Politicas:
--   - UPSERT via UNIQUE(tenant_id, voomp_contrato_id) -- preserva UUIDs
--   - valor_oferta vem da Recorrencia atual = 1 (primeira parcela)
--   - status_contrato e demais campos: ultimo valor nao-nulo
--   - Assinatura sem ID Contrato => raw_lines_skipped (CONTRATO_SEM_ID)
-- ============================================================

CREATE OR REPLACE FUNCTION unipds.upsert_contracts_from_raw(p_modo text DEFAULT 'full')
RETURNS TABLE(inseridos bigint, atualizados bigint, skipped bigint)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_inseridos   bigint := 0;
    v_atualizados bigint := 0;
    v_skipped     bigint := 0;
BEGIN
    -- ETAPA 1: Assinatura sem ID Contrato -> inbox
    WITH inserted_skip AS (
        INSERT INTO unipds.raw_lines_skipped
            (line_id, import_id, payload, motivo_skip, status_raw)
        SELECT
            rl.line_id, rl.import_id, rl.payload, 'CONTRATO_SEM_ID',
            rl.payload->>'Status da venda'
        FROM unipds.raw_lines rl
        WHERE rl.payload->>'Tipo de cobrança' = 'Assinatura'
          AND NULLIF(trim(rl.payload->>'ID Contrato'), '') IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM unipds.raw_lines_skipped s
              WHERE s.line_id = rl.line_id AND s.motivo_skip = 'CONTRATO_SEM_ID'
          )
        RETURNING skip_id
    )
    SELECT count(*) INTO v_skipped FROM inserted_skip;

    -- ETAPA 2: Consolidar assinaturas validas
    WITH raw_assinaturas AS (
        SELECT
            f.tenant_id,
            f.fonte_id,
            trim(rl.payload->>'ID Contrato')        AS voomp_contrato_id,
            regexp_replace(rl.payload->>'CPF/CNPJ', '[^0-9]', '', 'g') AS cpf_cnpj,
            trim(rl.payload->>'ID Produto')         AS voomp_produto_id,
            NULLIF(trim(rl.payload->>'ID Oferta'), '')                    AS voomp_oferta_id,
            NULLIF(trim(rl.payload->>'Nome da oferta'), '')               AS nome_oferta,
            NULLIF(trim(rl.payload->>'Período'), '')                      AS periodo,
            NULLIF(rl.payload->>'Recorrência total', '')::numeric::int    AS recorrencia_total,
            NULLIF(rl.payload->>'Valor Oferta', '')::numeric              AS valor_oferta,
            NULLIF(trim(rl.payload->>'Status de Contrato'), '')           AS status_contrato,
            NULLIF(rl.payload->>'Data da venda', '')::timestamp::date     AS data_venda,
            NULLIF(rl.payload->>'Recorrência atual', '')::numeric::int    AS recorrencia_atual,
            rl.processed_at
        FROM unipds.raw_lines rl
        JOIN unipds.raw_imports ri ON ri.import_id = rl.import_id
        JOIN unipds.fontes f       ON f.fonte_id = ri.fonte_id
        WHERE rl.payload->>'Tipo de cobrança' = 'Assinatura'
          AND NULLIF(trim(rl.payload->>'ID Contrato'), '') IS NOT NULL
          AND regexp_replace(COALESCE(rl.payload->>'CPF/CNPJ',''), '[^0-9]', '', 'g') <> ''
          AND NULLIF(trim(rl.payload->>'ID Produto'), '') IS NOT NULL
    ),
    consolidado AS (
        SELECT
            ra.tenant_id,
            (array_remove(array_agg(ra.fonte_id ORDER BY ra.processed_at DESC), NULL))[1] AS fonte_id,
            ra.voomp_contrato_id,
            -- student_id e product_id resolvidos via JOIN
            (array_remove(array_agg(ra.cpf_cnpj         ORDER BY ra.processed_at DESC), NULL))[1] AS cpf_cnpj,
            (array_remove(array_agg(ra.voomp_produto_id ORDER BY ra.processed_at DESC), NULL))[1] AS voomp_produto_id,
            (array_remove(array_agg(ra.voomp_oferta_id  ORDER BY ra.processed_at DESC), NULL))[1] AS voomp_oferta_id,
            (array_remove(array_agg(ra.nome_oferta      ORDER BY ra.processed_at DESC), NULL))[1] AS nome_oferta,
            (array_remove(array_agg(ra.periodo          ORDER BY ra.processed_at DESC), NULL))[1] AS periodo,
            (array_remove(array_agg(ra.recorrencia_total ORDER BY ra.processed_at DESC), NULL))[1] AS recorrencia_total,
            -- valor_oferta vem da linha de Recorrencia atual = 1 (primeira parcela)
            (array_remove(array_agg(ra.valor_oferta ORDER BY (ra.recorrencia_atual = 1) DESC, ra.processed_at DESC), NULL))[1] AS valor_oferta,
            (array_remove(array_agg(ra.status_contrato  ORDER BY ra.processed_at DESC), NULL))[1] AS status_contrato,
            -- data primeira venda = MIN da Data da venda das linhas
            min(ra.data_venda) AS data_primeira_venda
        FROM raw_assinaturas ra
        GROUP BY ra.tenant_id, ra.voomp_contrato_id
    ),
    enriquecido AS (
        SELECT
            c.tenant_id,
            c.fonte_id,
            s.student_id,
            p.product_id,
            c.voomp_contrato_id,
            c.voomp_oferta_id,
            c.nome_oferta,
            'Assinatura'::text AS tipo_cobranca,
            c.periodo,
            c.recorrencia_total,
            c.valor_oferta,
            c.status_contrato,
            c.data_primeira_venda
        FROM consolidado c
        JOIN unipds.students s ON s.tenant_id = c.tenant_id AND s.cpf_cnpj = c.cpf_cnpj
        JOIN unipds.products p ON p.tenant_id = c.tenant_id AND p.voomp_produto_id = c.voomp_produto_id
        WHERE c.valor_oferta IS NOT NULL
          AND c.status_contrato IS NOT NULL
    ),
    upserted AS (
        INSERT INTO unipds.contracts
            (tenant_id, fonte_id, student_id, product_id, voomp_contrato_id,
             voomp_oferta_id, nome_oferta, tipo_cobranca, periodo,
             recorrencia_total, valor_oferta, status_contrato, data_primeira_venda)
        SELECT tenant_id, fonte_id, student_id, product_id, voomp_contrato_id,
               voomp_oferta_id, nome_oferta, tipo_cobranca, periodo,
               recorrencia_total, valor_oferta, status_contrato, data_primeira_venda
        FROM enriquecido
        ON CONFLICT (tenant_id, voomp_contrato_id) DO UPDATE
        SET
            fonte_id            = EXCLUDED.fonte_id,
            student_id          = EXCLUDED.student_id,
            product_id          = EXCLUDED.product_id,
            voomp_oferta_id     = EXCLUDED.voomp_oferta_id,
            nome_oferta         = EXCLUDED.nome_oferta,
            periodo             = EXCLUDED.periodo,
            recorrencia_total   = EXCLUDED.recorrencia_total,
            valor_oferta        = EXCLUDED.valor_oferta,
            status_contrato     = EXCLUDED.status_contrato,
            data_primeira_venda = EXCLUDED.data_primeira_venda,
            updated_at          = now()
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

COMMENT ON FUNCTION unipds.upsert_contracts_from_raw(text) IS
  'Consolida raw_lines em contracts (apenas assinaturas com ID Contrato). UPSERT via UNIQUE(tenant_id, voomp_contrato_id). valor_oferta da Recorrencia atual=1. Resolve FKs via JOIN students/products.';
