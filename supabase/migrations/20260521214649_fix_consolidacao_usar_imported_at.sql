-- ============================================================
-- Fix: consolidacao por ORDER BY imported_at + linha_numero
--
-- Problema: as 5 funcoes de ETL ordenavam por rl.processed_at DESC
-- para pegar "o ultimo valor nao-nulo" de cada campo no consolidado.
-- Porem raw_lines.processed_at nunca eh populado (NULL em 100% das
-- linhas), entao a ordenacao virava aleatoria. Resultado: cada campo
-- do consolidado podia vir de uma linha raw diferente, gerando
-- registros inconsistentes (ex: categoria=ABERTO + data_pagamento
-- preenchida vinda da linha PAGA mais recente).
--
-- Fix: trocar ORDER BY processed_at DESC por
--      ORDER BY ri.imported_at DESC, rl.linha_numero ASC
--   - imported_at: sempre existe, identifica a importacao mais recente
--   - linha_numero: desempate deterministico dentro da mesma importacao
--
-- Apos esta migration, rodar processar_raw_lines('full') para
-- reprocessar todas as raw_lines com a ordenacao correta. O UPSERT
-- vai sobrescrever os valores stale de charges/payment_attempts/
-- students/contracts/products.
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1) upsert_products_from_raw
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION unipds.upsert_products_from_raw(p_modo text DEFAULT 'full')
RETURNS TABLE(inseridos bigint, atualizados bigint, skipped bigint)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_inseridos   bigint := 0;
    v_atualizados bigint := 0;
    v_skipped     bigint := 0;
BEGIN
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

    WITH raw_validas AS (
        SELECT
            f.tenant_id,
            trim(rl.payload->>'ID Produto')                  AS voomp_produto_id,
            NULLIF(trim(rl.payload->>'Nome do produto'), '')  AS nome,
            NULLIF(trim(rl.payload->>'Tipo do produto'), '')  AS tipo,
            NULLIF(trim(rl.payload->>'Categoria'), '')        AS categoria,
            ri.imported_at,
            rl.linha_numero
        FROM unipds.raw_lines rl
        JOIN unipds.raw_imports ri ON ri.import_id = rl.import_id
        JOIN unipds.fontes f       ON f.fonte_id = ri.fonte_id
        WHERE NULLIF(trim(rl.payload->>'ID Produto'), '') IS NOT NULL
    ),
    consolidado AS (
        SELECT
            tenant_id,
            voomp_produto_id,
            (array_remove(array_agg(nome      ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS nome,
            (array_remove(array_agg(tipo      ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS tipo,
            (array_remove(array_agg(categoria ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS categoria
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


-- ────────────────────────────────────────────────────────────
-- 2) upsert_students_from_raw
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION unipds.upsert_students_from_raw(p_modo text DEFAULT 'full')
RETURNS TABLE(inseridos bigint, atualizados bigint, skipped_cpf bigint, skipped_lead bigint)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_inseridos    bigint := 0;
    v_atualizados  bigint := 0;
    v_skipped_cpf  bigint := 0;
    v_skipped_lead bigint := 0;
BEGIN
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

    WITH base AS (
        SELECT
            rl.line_id, rl.import_id, rl.payload,
            f.tenant_id,
            regexp_replace(rl.payload->>'CPF/CNPJ', '[^0-9]', '', 'g') AS cpf_cnpj,
            rl.payload->>'Tipo de cobrança'   AS tipo,
            rl.payload->>'Status da venda'    AS status_venda,
            CASE WHEN rl.payload->>'Recorrência atual' IN ('','Indeterminado') THEN NULL
                 ELSE (rl.payload->>'Recorrência atual')::numeric::int END AS recorrencia_atual
        FROM unipds.raw_lines rl
        JOIN unipds.raw_imports ri ON ri.import_id = rl.import_id
        JOIN unipds.fontes f       ON f.fonte_id = ri.fonte_id
        WHERE regexp_replace(COALESCE(rl.payload->>'CPF/CNPJ',''), '[^0-9]', '', 'g') <> ''
    ),
    alunos AS (
        SELECT DISTINCT tenant_id, cpf_cnpj
        FROM base
        WHERE status_venda = 'Pago'
          AND (
              tipo = 'Único'
              OR (tipo = 'Assinatura' AND recorrencia_atual = 1)
          )
    ),
    leads AS (
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

    WITH base AS (
        SELECT
            f.tenant_id,
            regexp_replace(rl.payload->>'CPF/CNPJ', '[^0-9]', '', 'g') AS cpf_cnpj,
            rl.payload->>'Tipo de cobrança'   AS tipo,
            rl.payload->>'Status da venda'    AS status_venda,
            CASE WHEN rl.payload->>'Recorrência atual' IN ('','Indeterminado') THEN NULL
                 ELSE (rl.payload->>'Recorrência atual')::numeric::int END AS recorrencia_atual,
            NULLIF(trim(rl.payload->>'Nome do comprador'), '')         AS nome,
            NULLIF(lower(trim(rl.payload->>'Email do comprador')), '') AS email,
            NULLIF(trim(rl.payload->>'Número de telefone'), '')        AS telefone,
            NULLIF(trim(rl.payload->>'UF Origem'), '')                 AS uf_origem,
            ri.imported_at,
            rl.linha_numero
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
            initcap((array_remove(array_agg(b.nome      ORDER BY b.imported_at DESC, b.linha_numero ASC), NULL))[1]) AS nome,
                     (array_remove(array_agg(b.email     ORDER BY b.imported_at DESC, b.linha_numero ASC), NULL))[1] AS email,
                     (array_remove(array_agg(b.telefone  ORDER BY b.imported_at DESC, b.linha_numero ASC), NULL))[1] AS telefone,
                     (array_remove(array_agg(b.uf_origem ORDER BY b.imported_at DESC, b.linha_numero ASC), NULL))[1] AS uf_origem
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


-- ────────────────────────────────────────────────────────────
-- 3) upsert_contracts_from_raw
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION unipds.upsert_contracts_from_raw(p_modo text DEFAULT 'full')
RETURNS TABLE(inseridos bigint, atualizados bigint, skipped bigint)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_inseridos   bigint := 0;
    v_atualizados bigint := 0;
    v_skipped     bigint := 0;
BEGIN
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

    WITH raw_assinaturas AS (
        SELECT
            f.tenant_id,
            f.fonte_id,
            regexp_replace(trim(rl.payload->>'ID Contrato'), '\.0+$', '')   AS voomp_contrato_id,
            regexp_replace(rl.payload->>'CPF/CNPJ', '[^0-9]', '', 'g')      AS cpf_cnpj,
            trim(rl.payload->>'ID Produto')                                  AS voomp_produto_id,
            NULLIF(trim(rl.payload->>'ID Oferta'), '')                       AS voomp_oferta_id,
            NULLIF(trim(rl.payload->>'Nome da oferta'), '')                  AS nome_oferta,
            NULLIF(trim(rl.payload->>'Período'), '')                         AS periodo,
            CASE
                WHEN rl.payload->>'Recorrência total' IN ('', 'Indeterminado') THEN NULL
                ELSE (rl.payload->>'Recorrência total')::numeric::int
            END                                                              AS recorrencia_total,
            NULLIF(rl.payload->>'Valor Oferta', '')::numeric                 AS valor_oferta,
            NULLIF(trim(rl.payload->>'Status de Contrato'), '')              AS status_contrato,
            NULLIF(rl.payload->>'Data da venda', '')::timestamp::date        AS data_venda,
            CASE
                WHEN rl.payload->>'Recorrência atual' IN ('', 'Indeterminado') THEN NULL
                ELSE (rl.payload->>'Recorrência atual')::numeric::int
            END                                                              AS recorrencia_atual,
            ri.imported_at,
            rl.linha_numero
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
            (array_remove(array_agg(ra.fonte_id          ORDER BY ra.imported_at DESC, ra.linha_numero ASC), NULL))[1] AS fonte_id,
            ra.voomp_contrato_id,
            (array_remove(array_agg(ra.cpf_cnpj          ORDER BY ra.imported_at DESC, ra.linha_numero ASC), NULL))[1] AS cpf_cnpj,
            (array_remove(array_agg(ra.voomp_produto_id  ORDER BY ra.imported_at DESC, ra.linha_numero ASC), NULL))[1] AS voomp_produto_id,
            (array_remove(array_agg(ra.voomp_oferta_id   ORDER BY ra.imported_at DESC, ra.linha_numero ASC), NULL))[1] AS voomp_oferta_id,
            (array_remove(array_agg(ra.nome_oferta       ORDER BY ra.imported_at DESC, ra.linha_numero ASC), NULL))[1] AS nome_oferta,
            (array_remove(array_agg(ra.periodo           ORDER BY ra.imported_at DESC, ra.linha_numero ASC), NULL))[1] AS periodo,
            (array_remove(array_agg(ra.recorrencia_total ORDER BY ra.imported_at DESC, ra.linha_numero ASC), NULL))[1] AS recorrencia_total,
            -- valor_oferta: prioriza linha onde recorrencia_atual=1, depois mais recente
            (array_remove(array_agg(ra.valor_oferta      ORDER BY (ra.recorrencia_atual = 1) DESC, ra.imported_at DESC, ra.linha_numero ASC), NULL))[1] AS valor_oferta,
            (array_remove(array_agg(ra.status_contrato   ORDER BY ra.imported_at DESC, ra.linha_numero ASC), NULL))[1] AS status_contrato,
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


-- ────────────────────────────────────────────────────────────
-- 4) insert_charges_from_raw
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION unipds.insert_charges_from_raw(p_modo text DEFAULT 'full')
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
            f.tenant_id,
            ri.imported_at,
            rl.linha_numero,
            unipds.classificar_raw_line(rl.payload) AS categoria_raw,
            regexp_replace(rl.payload->>'CPF/CNPJ', '[^0-9]', '', 'g')                   AS cpf_cnpj,
            trim(rl.payload->>'ID Produto')                                               AS voomp_produto_id,
            regexp_replace(trim(COALESCE(rl.payload->>'ID Contrato', '')), '\.0+$', '')  AS voomp_contrato_id,
            rl.payload->>'ID Venda'                                                       AS voomp_venda_id,
            rl.payload->>'Tipo de cobrança'                                               AS tipo_cobranca,
            rl.payload->>'Status da venda'                                                AS status_voomp,
            CASE WHEN rl.payload->>'Recorrência atual' IN ('','Indeterminado') THEN NULL
                 ELSE (rl.payload->>'Recorrência atual')::numeric::int END                AS numero_parcela,
            NULLIF(rl.payload->>'Valor Oferta', '')::numeric                              AS valor_oferta_linha,
            NULLIF(rl.payload->>'Valor Pago', '')::numeric                                AS valor_pago,
            NULLIF(rl.payload->>'Taxa Voomp', '')::numeric                                AS taxa_voomp,
            NULLIF(rl.payload->>'Comissão Coprodutor', '')::numeric                       AS comissao_coprodutor,
            NULLIF(rl.payload->>'Valor Recebido', '')::numeric                            AS valor_recebido,
            NULLIF(trim(rl.payload->>'Cupom'), '')                                        AS cupom,
            NULLIF(trim(rl.payload->>'Método de pagamento'), '')                          AS metodo_pagamento,
            CASE WHEN rl.payload->>'Forma de pagamento' ~ '^[0-9]+$'
                 THEN (rl.payload->>'Forma de pagamento')::int END                        AS forma_pagamento,
            COALESCE(
                NULLIF(rl.payload->>'Data de vencimento do boleto', '')::date,
                NULLIF(rl.payload->>'Data da venda', '')::timestamp::date
            )                                                                             AS data_vencimento,
            NULLIF(rl.payload->>'Data de pagamento', '')::timestamp::date                 AS data_pagamento,
            NULLIF(rl.payload->>'Data liberação do saldo', '')::timestamp::date           AS data_liberacao_saldo
        FROM unipds.raw_lines rl
        JOIN unipds.raw_imports ri ON ri.import_id = rl.import_id
        JOIN unipds.fontes f       ON f.fonte_id   = ri.fonte_id
        WHERE unipds.classificar_raw_line(rl.payload) IN
              ('CHARGE_PAGO','CHARGE_ABERTO','CHARGE_REEMBOLSADO','CHARGE_CHARGEBACK')
    ),
    filtrado AS (
        SELECT b.*
        FROM base b
        WHERE EXISTS (
            SELECT 1 FROM unipds.students s
            WHERE s.tenant_id = b.tenant_id AND s.cpf_cnpj = b.cpf_cnpj
        )
    ),
    consolidado AS (
        SELECT
            voomp_venda_id,
            (array_remove(array_agg(tenant_id            ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS tenant_id,
            (array_remove(array_agg(cpf_cnpj             ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS cpf_cnpj,
            (array_remove(array_agg(voomp_produto_id     ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS voomp_produto_id,
            (array_remove(array_agg(NULLIF(voomp_contrato_id,'') ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS voomp_contrato_id,
            (array_remove(array_agg(tipo_cobranca        ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS tipo_cobranca,
            (array_remove(array_agg(categoria_raw        ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS categoria_raw,
            (array_remove(array_agg(status_voomp         ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS status_voomp,
            (array_remove(array_agg(numero_parcela       ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS numero_parcela,
            (array_remove(array_agg(valor_oferta_linha   ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS valor_oferta_linha,
            (array_remove(array_agg(valor_pago           ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS valor_pago,
            (array_remove(array_agg(taxa_voomp           ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS taxa_voomp,
            (array_remove(array_agg(comissao_coprodutor  ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS comissao_coprodutor,
            (array_remove(array_agg(valor_recebido       ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS valor_recebido,
            (array_remove(array_agg(cupom                ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS cupom,
            (array_remove(array_agg(metodo_pagamento     ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS metodo_pagamento,
            (array_remove(array_agg(forma_pagamento      ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS forma_pagamento,
            (array_remove(array_agg(data_vencimento      ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS data_vencimento,
            (array_remove(array_agg(data_pagamento       ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS data_pagamento,
            (array_remove(array_agg(data_liberacao_saldo ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS data_liberacao_saldo
        FROM filtrado
        GROUP BY voomp_venda_id
    ),
    enriquecido AS (
        SELECT
            c.voomp_venda_id,
            c.tenant_id,
            s.student_id,
            p.product_id,
            ct.contract_id,
            c.tipo_cobranca,
            replace(c.categoria_raw, 'CHARGE_', '') AS categoria,
            c.status_voomp AS status,
            c.numero_parcela,
            c.valor_oferta_linha,
            CASE c.categoria_raw
                WHEN 'CHARGE_PAGO'        THEN c.valor_pago
                WHEN 'CHARGE_ABERTO'      THEN c.valor_oferta_linha
                WHEN 'CHARGE_REEMBOLSADO' THEN c.valor_pago
                WHEN 'CHARGE_CHARGEBACK'  THEN c.valor_pago
            END AS valor_cobrado,
            c.taxa_voomp, c.comissao_coprodutor, c.valor_recebido,
            c.cupom, c.metodo_pagamento, c.forma_pagamento,
            c.data_vencimento, c.data_pagamento, c.data_liberacao_saldo,
            CASE
                WHEN c.categoria_raw = 'CHARGE_ABERTO'
                 AND c.data_vencimento IS NOT NULL
                 AND c.data_vencimento < CURRENT_DATE
                THEN (CURRENT_DATE - c.data_vencimento)
                ELSE 0
            END AS dias_atraso
        FROM consolidado c
        JOIN unipds.students s ON s.tenant_id = c.tenant_id AND s.cpf_cnpj = c.cpf_cnpj
        JOIN unipds.products p ON p.tenant_id = c.tenant_id AND p.voomp_produto_id = c.voomp_produto_id
        LEFT JOIN unipds.contracts ct ON ct.tenant_id = c.tenant_id
                                      AND ct.voomp_contrato_id = c.voomp_contrato_id
        WHERE
            CASE c.categoria_raw
                WHEN 'CHARGE_PAGO'        THEN c.valor_pago
                WHEN 'CHARGE_ABERTO'      THEN c.valor_oferta_linha
                WHEN 'CHARGE_REEMBOLSADO' THEN c.valor_pago
                WHEN 'CHARGE_CHARGEBACK'  THEN c.valor_pago
            END IS NOT NULL
    ),
    upserted AS (
        INSERT INTO unipds.charges
            (voomp_venda_id, tenant_id, student_id, product_id, contract_id,
             tipo_cobranca, categoria, status,
             numero_parcela, valor_oferta_linha, valor_cobrado,
             taxa_voomp, comissao_coprodutor, valor_recebido,
             cupom, metodo_pagamento, forma_pagamento,
             data_vencimento, data_pagamento, data_liberacao_saldo,
             dias_atraso)
        SELECT voomp_venda_id, tenant_id, student_id, product_id, contract_id,
               tipo_cobranca, categoria, status,
               numero_parcela, valor_oferta_linha, valor_cobrado,
               taxa_voomp, comissao_coprodutor, valor_recebido,
               cupom, metodo_pagamento, forma_pagamento,
               data_vencimento, data_pagamento, data_liberacao_saldo,
               dias_atraso
        FROM enriquecido
        ON CONFLICT (voomp_venda_id) DO UPDATE
        SET
            tenant_id=EXCLUDED.tenant_id, student_id=EXCLUDED.student_id,
            product_id=EXCLUDED.product_id, contract_id=EXCLUDED.contract_id,
            tipo_cobranca=EXCLUDED.tipo_cobranca, categoria=EXCLUDED.categoria,
            status=EXCLUDED.status, numero_parcela=EXCLUDED.numero_parcela,
            valor_oferta_linha=EXCLUDED.valor_oferta_linha,
            valor_cobrado=EXCLUDED.valor_cobrado,
            taxa_voomp=EXCLUDED.taxa_voomp,
            comissao_coprodutor=EXCLUDED.comissao_coprodutor,
            valor_recebido=EXCLUDED.valor_recebido,
            cupom=EXCLUDED.cupom,
            metodo_pagamento=EXCLUDED.metodo_pagamento,
            forma_pagamento=EXCLUDED.forma_pagamento,
            data_vencimento=EXCLUDED.data_vencimento,
            data_pagamento=EXCLUDED.data_pagamento,
            data_liberacao_saldo=EXCLUDED.data_liberacao_saldo,
            dias_atraso=EXCLUDED.dias_atraso
        RETURNING (xmax = 0) AS inserted
    )
    SELECT count(*) FILTER (WHERE inserted), count(*) FILTER (WHERE NOT inserted)
    INTO v_inseridos, v_atualizados
    FROM upserted;

    RETURN QUERY SELECT v_inseridos, v_atualizados;
END;
$function$;


-- ────────────────────────────────────────────────────────────
-- 5) insert_payment_attempts_from_raw
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION unipds.insert_payment_attempts_from_raw(p_modo text DEFAULT 'full')
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
            f.tenant_id,
            ri.imported_at,
            rl.linha_numero,
            unipds.classificar_raw_line(rl.payload) AS categoria_raw,
            regexp_replace(rl.payload->>'CPF/CNPJ', '[^0-9]', '', 'g')                   AS cpf_cnpj,
            trim(rl.payload->>'ID Produto')                                               AS voomp_produto_id,
            regexp_replace(trim(COALESCE(rl.payload->>'ID Contrato', '')), '\.0+$', '')  AS voomp_contrato_id,
            rl.payload->>'ID Venda'                                                       AS voomp_venda_id,
            rl.payload->>'Tipo de cobrança'                                               AS tipo_cobranca,
            rl.payload->>'Status da venda'                                                AS status_voomp,
            CASE WHEN rl.payload->>'Recorrência atual' IN ('','Indeterminado') THEN NULL
                 ELSE (rl.payload->>'Recorrência atual')::numeric::int END                AS numero_parcela,
            NULLIF(rl.payload->>'Valor Oferta', '')::numeric                              AS valor_oferta_linha,
            NULLIF(rl.payload->>'Taxa Voomp', '')::numeric                                AS taxa_voomp,
            NULLIF(trim(rl.payload->>'Método de pagamento'), '')                          AS metodo_pagamento,
            CASE WHEN rl.payload->>'Forma de pagamento' ~ '^[0-9]+$'
                 THEN (rl.payload->>'Forma de pagamento')::int END                        AS forma_pagamento,
            COALESCE(
                NULLIF(rl.payload->>'Data de vencimento do boleto', '')::date,
                NULLIF(rl.payload->>'Data da venda', '')::timestamp::date
            )                                                                             AS data_tentativa,
            NULLIF(trim(rl.payload->>'Motivo da recusa'), '')                             AS motivo_recusa
        FROM unipds.raw_lines rl
        JOIN unipds.raw_imports ri ON ri.import_id = rl.import_id
        JOIN unipds.fontes f       ON f.fonte_id   = ri.fonte_id
        WHERE unipds.classificar_raw_line(rl.payload) = 'TENTATIVA_RECUSADA'
    ),
    filtrado AS (
        SELECT b.*
        FROM base b
        WHERE EXISTS (
            SELECT 1 FROM unipds.students s
            WHERE s.tenant_id = b.tenant_id AND s.cpf_cnpj = b.cpf_cnpj
        )
    ),
    consolidado AS (
        SELECT
            voomp_venda_id,
            (array_remove(array_agg(tenant_id          ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS tenant_id,
            (array_remove(array_agg(cpf_cnpj           ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS cpf_cnpj,
            (array_remove(array_agg(voomp_produto_id   ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS voomp_produto_id,
            (array_remove(array_agg(NULLIF(voomp_contrato_id,'') ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS voomp_contrato_id,
            (array_remove(array_agg(tipo_cobranca      ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS tipo_cobranca,
            (array_remove(array_agg(categoria_raw      ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS categoria_raw,
            (array_remove(array_agg(status_voomp       ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS status_voomp,
            (array_remove(array_agg(numero_parcela     ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS numero_parcela,
            (array_remove(array_agg(valor_oferta_linha ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS valor_oferta_linha,
            (array_remove(array_agg(taxa_voomp         ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS taxa_voomp,
            (array_remove(array_agg(metodo_pagamento   ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS metodo_pagamento,
            (array_remove(array_agg(forma_pagamento    ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS forma_pagamento,
            (array_remove(array_agg(data_tentativa     ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS data_tentativa,
            (array_remove(array_agg(motivo_recusa      ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS motivo_recusa
        FROM filtrado
        GROUP BY voomp_venda_id
    ),
    enriquecido AS (
        SELECT
            c.voomp_venda_id,
            c.tenant_id,
            s.student_id,
            p.product_id,
            ct.contract_id,
            c.tipo_cobranca,
            'TENTATIVA_RECUSADA' AS categoria,
            c.status_voomp AS status,
            c.numero_parcela,
            c.valor_oferta_linha AS valor_cobrado,
            c.taxa_voomp,
            c.metodo_pagamento,
            c.forma_pagamento,
            c.data_tentativa,
            c.motivo_recusa
        FROM consolidado c
        JOIN unipds.students s ON s.tenant_id = c.tenant_id AND s.cpf_cnpj = c.cpf_cnpj
        JOIN unipds.products p ON p.tenant_id = c.tenant_id AND p.voomp_produto_id = c.voomp_produto_id
        LEFT JOIN unipds.contracts ct ON ct.tenant_id = c.tenant_id
                                      AND ct.voomp_contrato_id = c.voomp_contrato_id
    ),
    upserted AS (
        INSERT INTO unipds.payment_attempts
            (voomp_venda_id, tenant_id, student_id, product_id, contract_id,
             tipo_cobranca, categoria, status,
             numero_parcela, valor_cobrado,
             taxa_voomp, metodo_pagamento, forma_pagamento,
             data_tentativa, motivo_recusa)
        SELECT voomp_venda_id, tenant_id, student_id, product_id, contract_id,
               tipo_cobranca, categoria, status,
               numero_parcela, valor_cobrado,
               taxa_voomp, metodo_pagamento, forma_pagamento,
               data_tentativa, motivo_recusa
        FROM enriquecido
        ON CONFLICT (voomp_venda_id) DO UPDATE
        SET
            tenant_id     = EXCLUDED.tenant_id,
            student_id    = EXCLUDED.student_id,
            product_id    = EXCLUDED.product_id,
            contract_id   = EXCLUDED.contract_id,
            tipo_cobranca = EXCLUDED.tipo_cobranca,
            categoria     = EXCLUDED.categoria,
            status        = EXCLUDED.status,
            numero_parcela= EXCLUDED.numero_parcela,
            valor_cobrado = EXCLUDED.valor_cobrado,
            taxa_voomp    = EXCLUDED.taxa_voomp,
            metodo_pagamento = EXCLUDED.metodo_pagamento,
            forma_pagamento  = EXCLUDED.forma_pagamento,
            data_tentativa   = EXCLUDED.data_tentativa,
            motivo_recusa    = EXCLUDED.motivo_recusa
        RETURNING (xmax = 0) AS inserted
    )
    SELECT count(*) FILTER (WHERE inserted), count(*) FILTER (WHERE NOT inserted)
    INTO v_inseridos, v_atualizados
    FROM upserted;

    RETURN QUERY SELECT v_inseridos, v_atualizados;
END;
$function$;
