-- ============================================================
-- Funcao insert_charges_from_raw
--
-- Popula charges com cobrancas reais (PAGO/ABERTO/REEMBOLSADO/CHARGEBACK)
-- de alunos qualificados. Tentativas recusadas vao para payment_attempts (2h).
--
-- Regua por pessoa: se CPF eh aluno (esta em students), toda cobranca
-- real entra. Se nao eh aluno, ja virou skipped em 2d.
--
-- Assinatura: contract_id via JOIN contracts.
-- Unica: contract_id = NULL (LEFT JOIN nao casa).
--
-- valor_cobrado:
--   CHARGE_PAGO/REEMBOLSADO/CHARGEBACK -> Valor Pago
--   CHARGE_ABERTO                       -> Valor Oferta
--
-- dias_atraso:
--   ABERTO + data_vencimento < hoje -> (hoje - data_vencimento)
--   else 0
--
-- status: original do Voomp ('Pago', 'Aguardando pagamento',
--         'Reembolsado', 'Chargeback')
-- categoria: normalizada (PAGO, ABERTO, REEMBOLSADO, CHARGEBACK)
--
-- UPSERT via UNIQUE(voomp_venda_id) - preserva UUIDs
-- ============================================================

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
            rl.processed_at,
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
    -- So charges de alunos qualificados
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
            (array_remove(array_agg(tenant_id             ORDER BY processed_at DESC), NULL))[1] AS tenant_id,
            (array_remove(array_agg(cpf_cnpj              ORDER BY processed_at DESC), NULL))[1] AS cpf_cnpj,
            (array_remove(array_agg(voomp_produto_id      ORDER BY processed_at DESC), NULL))[1] AS voomp_produto_id,
            (array_remove(array_agg(NULLIF(voomp_contrato_id,'') ORDER BY processed_at DESC), NULL))[1] AS voomp_contrato_id,
            (array_remove(array_agg(tipo_cobranca         ORDER BY processed_at DESC), NULL))[1] AS tipo_cobranca,
            (array_remove(array_agg(categoria_raw         ORDER BY processed_at DESC), NULL))[1] AS categoria_raw,
            (array_remove(array_agg(status_voomp          ORDER BY processed_at DESC), NULL))[1] AS status_voomp,
            (array_remove(array_agg(numero_parcela        ORDER BY processed_at DESC), NULL))[1] AS numero_parcela,
            (array_remove(array_agg(valor_oferta_linha    ORDER BY processed_at DESC), NULL))[1] AS valor_oferta_linha,
            (array_remove(array_agg(valor_pago            ORDER BY processed_at DESC), NULL))[1] AS valor_pago,
            (array_remove(array_agg(taxa_voomp            ORDER BY processed_at DESC), NULL))[1] AS taxa_voomp,
            (array_remove(array_agg(comissao_coprodutor   ORDER BY processed_at DESC), NULL))[1] AS comissao_coprodutor,
            (array_remove(array_agg(valor_recebido        ORDER BY processed_at DESC), NULL))[1] AS valor_recebido,
            (array_remove(array_agg(cupom                 ORDER BY processed_at DESC), NULL))[1] AS cupom,
            (array_remove(array_agg(metodo_pagamento      ORDER BY processed_at DESC), NULL))[1] AS metodo_pagamento,
            (array_remove(array_agg(forma_pagamento       ORDER BY processed_at DESC), NULL))[1] AS forma_pagamento,
            (array_remove(array_agg(data_vencimento       ORDER BY processed_at DESC), NULL))[1] AS data_vencimento,
            (array_remove(array_agg(data_pagamento        ORDER BY processed_at DESC), NULL))[1] AS data_pagamento,
            (array_remove(array_agg(data_liberacao_saldo  ORDER BY processed_at DESC), NULL))[1] AS data_liberacao_saldo
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
            -- Normaliza categoria removendo prefixo CHARGE_
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
            -- dias_atraso so para ABERTO atrasado
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
        -- valor_cobrado tem que existir (NOT NULL na tabela)
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

COMMENT ON FUNCTION unipds.insert_charges_from_raw(text) IS
  'Popula charges (PAGO/ABERTO/REEMBOLSADO/CHARGEBACK) de alunos. UPSERT via voomp_venda_id. Status = original Voomp; categoria = normalizada. dias_atraso so para ABERTO atrasado.';
