-- ============================================================
-- Funcao upsert_students_from_raw (v2 - apenas alunos)
--
-- Regua de ouro: students contem APENAS alunos.
-- Aluno = pessoa com pelo menos:
--   - 1 charge Pago em Tipo='Assinatura' com Recorrencia atual=1 (P1 paga), OU
--   - 1 charge Pago em Tipo='Único' (venda a vista paga)
--
-- CPFs que nao se qualificam = leads. Vao para raw_lines_skipped
-- (motivo LEAD_NAO_CONVERTIDO).
--
-- Politicas mantidas:
--   - CPF/CNPJ vazio => skipped CPF_INVALIDO
--   - Normalizacao: CPF so digitos, nome INITCAP, email LOWER
--   - Ultimo valor nao-nulo por campo
--
-- DROP + CREATE necessario: RETURNS TABLE mudou de 3 para 4 colunas.
-- ============================================================

DROP FUNCTION IF EXISTS unipds.upsert_students_from_raw(text);

CREATE FUNCTION unipds.upsert_students_from_raw(p_modo text DEFAULT 'full')
RETURNS TABLE(inseridos bigint, atualizados bigint, skipped_cpf bigint, skipped_lead bigint)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_inseridos    bigint := 0;
    v_atualizados  bigint := 0;
    v_skipped_cpf  bigint := 0;
    v_skipped_lead bigint := 0;
BEGIN
    -- ETAPA 1: CPF/CNPJ invalido -> inbox
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
    SELECT count(*) INTO v_skipped_cpf FROM inserted_skip;

    -- ETAPA 2: Identificar alunos qualificados (P1 paga ou unica paga)
    -- ETAPA 3: Lead = CPF com CPF valido mas sem qualificacao -> inbox
    WITH base AS (
        SELECT
            rl.line_id, rl.import_id, rl.payload,
            f.tenant_id,
            regexp_replace(rl.payload->>'CPF/CNPJ', '[^0-9]', '', 'g') AS cpf_cnpj,
            rl.payload->>'Tipo de cobrança'   AS tipo,
            rl.payload->>'Status da venda'     AS status_venda,
            CASE WHEN rl.payload->>'Recorrência atual' IN ('','Indeterminado') THEN NULL
                 ELSE (rl.payload->>'Recorrência atual')::numeric::int END AS recorrencia_atual
        FROM unipds.raw_lines rl
        JOIN unipds.raw_imports ri ON ri.import_id = rl.import_id
        JOIN unipds.fontes f       ON f.fonte_id = ri.fonte_id
        WHERE regexp_replace(COALESCE(rl.payload->>'CPF/CNPJ',''), '[^0-9]', '', 'g') <> ''
    ),
    alunos AS (
        -- CPFs que se qualificam como aluno
        SELECT DISTINCT tenant_id, cpf_cnpj
        FROM base
        WHERE status_venda = 'Pago'
          AND (
              tipo = 'Único'
              OR (tipo = 'Assinatura' AND recorrencia_atual = 1)
          )
    ),
    leads AS (
        -- CPFs com CPF valido que nao se qualificam = leads
        SELECT DISTINCT b.line_id, b.import_id, b.payload, b.status_venda
        FROM base b
        WHERE NOT EXISTS (
            SELECT 1 FROM alunos a
            WHERE a.tenant_id = b.tenant_id AND a.cpf_cnpj = b.cpf_cnpj
        )
    ),
    inserted_lead_skip AS (
        INSERT INTO unipds.raw_lines_skipped
            (line_id, import_id, payload, motivo_skip, status_raw)
        SELECT l.line_id, l.import_id, l.payload, 'LEAD_NAO_CONVERTIDO', l.status_venda
        FROM leads l
        WHERE NOT EXISTS (
            SELECT 1 FROM unipds.raw_lines_skipped s
            WHERE s.line_id = l.line_id AND s.motivo_skip = 'LEAD_NAO_CONVERTIDO'
        )
        RETURNING skip_id
    )
    SELECT count(*) INTO v_skipped_lead FROM inserted_lead_skip;

    -- ETAPA 4: Consolidar e upsert apenas alunos qualificados
    WITH base AS (
        SELECT
            f.tenant_id,
            regexp_replace(rl.payload->>'CPF/CNPJ', '[^0-9]', '', 'g') AS cpf_cnpj,
            rl.payload->>'Tipo de cobrança'   AS tipo,
            rl.payload->>'Status da venda'     AS status_venda,
            CASE WHEN rl.payload->>'Recorrência atual' IN ('','Indeterminado') THEN NULL
                 ELSE (rl.payload->>'Recorrência atual')::numeric::int END AS recorrencia_atual,
            NULLIF(trim(rl.payload->>'Nome do comprador'), '')         AS nome,
            NULLIF(lower(trim(rl.payload->>'Email do comprador')), '') AS email,
            NULLIF(trim(rl.payload->>'Número de telefone'), '')        AS telefone,
            NULLIF(trim(rl.payload->>'UF Origem'), '')                 AS uf_origem,
            rl.processed_at
        FROM unipds.raw_lines rl
        JOIN unipds.raw_imports ri ON ri.import_id = rl.import_id
        JOIN unipds.fontes f       ON f.fonte_id = ri.fonte_id
        WHERE regexp_replace(COALESCE(rl.payload->>'CPF/CNPJ',''), '[^0-9]', '', 'g') <> ''
    ),
    alunos AS (
        SELECT DISTINCT tenant_id, cpf_cnpj
        FROM base
        WHERE status_venda = 'Pago'
          AND (tipo = 'Único' OR (tipo = 'Assinatura' AND recorrencia_atual = 1))
    ),
    consolidado AS (
        SELECT
            b.tenant_id,
            b.cpf_cnpj,
            initcap((array_remove(array_agg(b.nome      ORDER BY b.processed_at DESC), NULL))[1]) AS nome,
                     (array_remove(array_agg(b.email     ORDER BY b.processed_at DESC), NULL))[1] AS email,
                     (array_remove(array_agg(b.telefone  ORDER BY b.processed_at DESC), NULL))[1] AS telefone,
                     (array_remove(array_agg(b.uf_origem ORDER BY b.processed_at DESC), NULL))[1] AS uf_origem
        FROM base b
        JOIN alunos a ON a.tenant_id = b.tenant_id AND a.cpf_cnpj = b.cpf_cnpj
        GROUP BY b.tenant_id, b.cpf_cnpj
    ),
    upserted AS (
        INSERT INTO unipds.students (tenant_id, cpf_cnpj, nome, email, telefone, uf_origem)
        SELECT tenant_id, cpf_cnpj, nome, email, telefone, uf_origem
        FROM consolidado
        ON CONFLICT (tenant_id, cpf_cnpj) DO UPDATE
        SET nome=EXCLUDED.nome, email=EXCLUDED.email, telefone=EXCLUDED.telefone,
            uf_origem=EXCLUDED.uf_origem, updated_at=now()
        RETURNING (xmax = 0) AS inserted
    )
    SELECT count(*) FILTER (WHERE inserted), count(*) FILTER (WHERE NOT inserted)
    INTO v_inseridos, v_atualizados
    FROM upserted;

    RETURN QUERY SELECT v_inseridos, v_atualizados, v_skipped_cpf, v_skipped_lead;
END;
$function$;

COMMENT ON FUNCTION unipds.upsert_students_from_raw(text) IS
  'Popula students APENAS com alunos: P1 paga (assinatura) ou unica paga. Leads vao para raw_lines_skipped (LEAD_NAO_CONVERTIDO).';
