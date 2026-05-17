-- ============================================================
-- Funcao upsert_students_from_raw
--
-- Consolida raw_lines em unipds.students, preservando UUIDs
-- existentes via chave natural (tenant_id, cpf_cnpj).
--
-- Politicas:
--   - Mais recente vence (ORDER BY processed_at DESC por campo)
--   - Por campo: ultimo valor nao-nulo entre todas as raw_lines do aluno
--   - Normalizacao: CPF/CNPJ so digitos, nome INITCAP, email LOWER
--   - CPF/CNPJ invalido => raw_lines_skipped (motivo CPF_INVALIDO)
--
-- Retorna: (inseridos, atualizados, skipped)
-- ============================================================

CREATE OR REPLACE FUNCTION unipds.upsert_students_from_raw(p_modo text DEFAULT 'full')
RETURNS TABLE(inseridos bigint, atualizados bigint, skipped bigint)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_inseridos   bigint := 0;
    v_atualizados bigint := 0;
    v_skipped     bigint := 0;
BEGIN
    -- ETAPA 1: Linhas com CPF/CNPJ invalido (vazio ou sem digitos) -> inbox
    WITH inserted_skip AS (
        INSERT INTO unipds.raw_lines_skipped
            (line_id, import_id, payload, motivo_skip, status_raw)
        SELECT
            rl.line_id, rl.import_id, rl.payload, 'CPF_INVALIDO',
            rl.payload->>'Status da venda'
        FROM unipds.raw_lines rl
        WHERE regexp_replace(COALESCE(rl.payload->>'CPF/CNPJ', ''), '[^0-9]', '', 'g') = ''
          AND NOT EXISTS (
              SELECT 1 FROM unipds.raw_lines_skipped s
              WHERE s.line_id = rl.line_id AND s.motivo_skip = 'CPF_INVALIDO'
          )
        RETURNING skip_id
    )
    SELECT count(*) INTO v_skipped FROM inserted_skip;

    -- ETAPA 2: Consolidar por aluno, pegando ultimo valor nao-nulo de cada campo
    WITH raw_validas AS (
        SELECT
            f.tenant_id,
            regexp_replace(rl.payload->>'CPF/CNPJ', '[^0-9]', '', 'g') AS cpf_cnpj,
            NULLIF(trim(rl.payload->>'Nome do comprador'), '')           AS nome,
            NULLIF(lower(trim(rl.payload->>'Email do comprador')), '')   AS email,
            NULLIF(trim(rl.payload->>'Número de telefone'), '')          AS telefone,
            NULLIF(trim(rl.payload->>'UF Origem'), '')                   AS uf_origem,
            rl.processed_at
        FROM unipds.raw_lines rl
        JOIN unipds.raw_imports ri ON ri.import_id = rl.import_id
        JOIN unipds.fontes f       ON f.fonte_id = ri.fonte_id
        WHERE regexp_replace(COALESCE(rl.payload->>'CPF/CNPJ',''), '[^0-9]', '', 'g') <> ''
    ),
    consolidado AS (
        SELECT
            tenant_id,
            cpf_cnpj,
            initcap((array_remove(array_agg(nome      ORDER BY processed_at DESC), NULL))[1]) AS nome,
                     (array_remove(array_agg(email     ORDER BY processed_at DESC), NULL))[1] AS email,
                     (array_remove(array_agg(telefone  ORDER BY processed_at DESC), NULL))[1] AS telefone,
                     (array_remove(array_agg(uf_origem ORDER BY processed_at DESC), NULL))[1] AS uf_origem
        FROM raw_validas
        GROUP BY tenant_id, cpf_cnpj
    ),
    upserted AS (
        INSERT INTO unipds.students (tenant_id, cpf_cnpj, nome, email, telefone, uf_origem)
        SELECT tenant_id, cpf_cnpj, nome, email, telefone, uf_origem
        FROM consolidado
        ON CONFLICT (tenant_id, cpf_cnpj) DO UPDATE
        SET
            nome       = EXCLUDED.nome,
            email      = EXCLUDED.email,
            telefone   = EXCLUDED.telefone,
            uf_origem  = EXCLUDED.uf_origem,
            updated_at = now()
        RETURNING (xmax = 0) AS inserted
    )
    SELECT
        count(*) FILTER (WHERE inserted)     AS ins,
        count(*) FILTER (WHERE NOT inserted) AS upd
    INTO v_inseridos, v_atualizados
    FROM upserted;

    RETURN QUERY SELECT v_inseridos, v_atualizados, v_skipped;
END;
$function$;

COMMENT ON FUNCTION unipds.upsert_students_from_raw(text) IS
  'Consolida raw_lines em students com normalizacao + ultimo valor nao-nulo por campo. Preserva UUIDs via UNIQUE(tenant_id, cpf_cnpj). CPF invalido vai para raw_lines_skipped.';
