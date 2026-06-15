-- ============================================================
-- Comprador no nivel da COBRANCA + views lendo o nome real.
--
-- Problema: students eh chaveado por CPF/CNPJ. Compras corporativas
-- (1 CNPJ, varios funcionarios) e alguns CPFs (comprador != aluno)
-- colapsam em 1 registro de aluno — o nome exibido eh o ultimo
-- processado, nao o da matricula. Ex: contrato 151886 (IA) mostra
-- "Arthur" sendo do "Marco Giroto".
--
-- Validado: dentro de um MESMO contrato o comprador NUNCA varia
-- (0 de 2.236 contratos ambiguos em IA). Logo a granularidade
-- comprador = cobranca/contrato resolve sem nenhuma decisao de
-- agregacao — "falha por contrato" eh impossivel por construcao.
--
-- Estrategia (toda no banco, fronts inalterados — leem as views):
--   1. charges += nome_comprador/email_comprador/telefone_comprador
--      (grao do arquivo: cada cobranca carrega o seu dono).
--   2. ETL insert_charges_from_raw passa a popular esses campos.
--   3. Helper vw_contrato_comprador (1 linha/contrato) — tambem
--      serve de view de auditoria "aluno real por contrato".
--   4. 6 views passam a exibir COALESCE(comprador, students.nome):
--      - grao charge  (v_evasao, v_matriculas_ativas): da propria charge
--      - grao contrato (vw_casos_cobranca, vw_reversoes,
--        vw_contratos_risco_cancelamento, vw_inadimplencia): do helper
--      COALESCE garante ZERO regressao em PF normal (fallback ao
--      students.nome); so os casos colapsados sao corrigidos.
--
-- cpf_cnpj NAO muda (o documento da compra continua correto — eh o
-- CNPJ da empresa mesmo). Backfill via reprocesso do ETL apos aplicar.
-- vw_casos_cobranca e vw_reversoes sao territorio da sessao de
-- cobranca (avisar): mudanca eh so COALESCE nas saidas de nome/
-- email/telefone — mesmas colunas, mesma ordem, mesmos tipos.
-- ============================================================

-- ─── 1. Colunas de comprador em charges ───────────────────────
ALTER TABLE unipds.charges
  ADD COLUMN IF NOT EXISTS nome_comprador     text,
  ADD COLUMN IF NOT EXISTS email_comprador    text,
  ADD COLUMN IF NOT EXISTS telefone_comprador text;

COMMENT ON COLUMN unipds.charges.nome_comprador IS
  'Nome do comprador desta cobranca (grao do arquivo Voomp). Resolve o colapso de students por CPF/CNPJ em compras corporativas.';

-- ─── 2. ETL: insert_charges_from_raw popula o comprador ───────
CREATE OR REPLACE FUNCTION unipds.insert_charges_from_raw(p_modo text DEFAULT 'full'::text)
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
            NULLIF(rl.payload->>'Data liberação do saldo', '')::timestamp::date           AS data_liberacao_saldo,
            NULLIF(trim(rl.payload->>'Nome do comprador'), '')                            AS nome_comprador,
            NULLIF(trim(rl.payload->>'Email do comprador'), '')                           AS email_comprador,
            NULLIF(regexp_replace(COALESCE(rl.payload->>'Número de telefone',''),'[^0-9]','','g'),'') AS telefone_comprador
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
            (array_remove(array_agg(data_liberacao_saldo ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS data_liberacao_saldo,
            (array_remove(array_agg(nome_comprador       ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS nome_comprador,
            (array_remove(array_agg(email_comprador      ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS email_comprador,
            (array_remove(array_agg(telefone_comprador   ORDER BY imported_at DESC, linha_numero ASC), NULL))[1] AS telefone_comprador
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
            c.nome_comprador, c.email_comprador, c.telefone_comprador,
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
             nome_comprador, email_comprador, telefone_comprador,
             dias_atraso)
        SELECT voomp_venda_id, tenant_id, student_id, product_id, contract_id,
               tipo_cobranca, categoria, status,
               numero_parcela, valor_oferta_linha, valor_cobrado,
               taxa_voomp, comissao_coprodutor, valor_recebido,
               cupom, metodo_pagamento, forma_pagamento,
               data_vencimento, data_pagamento, data_liberacao_saldo,
               nome_comprador, email_comprador, telefone_comprador,
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
            nome_comprador=EXCLUDED.nome_comprador,
            email_comprador=EXCLUDED.email_comprador,
            telefone_comprador=EXCLUDED.telefone_comprador,
            dias_atraso=EXCLUDED.dias_atraso
        RETURNING (xmax = 0) AS inserted
    )
    SELECT count(*) FILTER (WHERE inserted), count(*) FILTER (WHERE NOT inserted)
    INTO v_inseridos, v_atualizados
    FROM upserted;

    RETURN QUERY SELECT v_inseridos, v_atualizados;
END;
$function$;

-- ─── 3. Helper / auditoria: 1 comprador por contrato ──────────
-- Comprador eh unico por contrato (validado). array_remove+[1] pega
-- o primeiro nao-nulo (P1 primeiro) — deterministico.
CREATE OR REPLACE VIEW unipds.vw_contrato_comprador AS
SELECT
    ch.contract_id,
    (array_remove(array_agg(ch.nome_comprador     ORDER BY ch.numero_parcela ASC NULLS LAST), NULL))[1] AS nome_comprador,
    (array_remove(array_agg(ch.email_comprador    ORDER BY ch.numero_parcela ASC NULLS LAST), NULL))[1] AS email_comprador,
    (array_remove(array_agg(ch.telefone_comprador ORDER BY ch.numero_parcela ASC NULLS LAST), NULL))[1] AS telefone_comprador
FROM unipds.charges ch
WHERE ch.contract_id IS NOT NULL
GROUP BY ch.contract_id;

COMMENT ON VIEW unipds.vw_contrato_comprador IS
  'Aluno real por contrato (1 linha/contrato), derivado de charges. Resolve o colapso de students por CPF/CNPJ. Tambem serve de auditoria do nome correto por matricula.';

GRANT SELECT ON unipds.vw_contrato_comprador TO anon, authenticated, service_role;

-- ─── 4. Views consumidoras com COALESCE(comprador, students) ──

-- 4a. v_evasao (grao charge)
CREATE OR REPLACE VIEW unipds.v_evasao AS
 SELECT c.charge_id,
    c.status,
    c.numero_parcela,
    c.metodo_pagamento,
    c.valor_cobrado,
    c.valor_recebido,
    c.data_pagamento,
    COALESCE(ct.voomp_contrato_id, c.voomp_venda_id) AS contract_ref,
    COALESCE(ct.nome_oferta, pr.nome) AS nome_oferta,
    c.tipo_cobranca,
    ct.recorrencia_total,
    ct.data_primeira_venda,
    c.tenant_id,
    COALESCE(c.nome_comprador, s.nome) AS nome,
    s.cpf_cnpj,
    t.nome AS tenant_nome,
    r.ocorrido_em::date AS ocorrido_em,
    r.tipo AS tipo_refund,
    r.valor AS valor_refund
   FROM unipds.charges c
     JOIN unipds.students s ON s.student_id = c.student_id
     JOIN unipds.tenants t ON t.tenant_id = c.tenant_id
     LEFT JOIN unipds.contracts ct ON ct.contract_id = c.contract_id
     LEFT JOIN unipds.products pr ON pr.product_id = c.product_id
     LEFT JOIN unipds.refunds r ON r.charge_id = c.charge_id
  WHERE c.categoria = ANY (ARRAY['REEMBOLSADO'::text, 'CHARGEBACK'::text]);

GRANT SELECT ON unipds.v_evasao TO anon, authenticated, service_role;

-- 4b. v_matriculas_ativas (grao charge)
CREATE OR REPLACE VIEW unipds.v_matriculas_ativas AS
 SELECT DISTINCT ON (ch.student_id, (COALESCE(ch.contract_id::text, ch.voomp_venda_id))) ch.student_id,
    COALESCE(ch.nome_comprador, s.nome) AS nome,
    s.cpf_cnpj,
    COALESCE(ct.voomp_contrato_id, ch.voomp_venda_id) AS contract_ref,
    pr.nome AS produto_nome,
        CASE
            WHEN ch.tipo_cobranca = 'Único'::text THEN 'UNICO'::text
            ELSE 'ASSINATURA'::text
        END AS modalidade,
    ch.data_pagamento AS data_matricula,
    COALESCE(ct.status_contrato, 'Pago'::text) AS status_contrato,
    ch.tenant_id,
    ch.product_id,
    vpc.classe AS tipo_curso
   FROM unipds.charges ch
     JOIN unipds.students s ON s.student_id = ch.student_id
     LEFT JOIN unipds.contracts ct ON ct.contract_id = ch.contract_id
     LEFT JOIN unipds.products pr ON pr.product_id = ch.product_id
     LEFT JOIN unipds.v_produtos_classificados vpc ON vpc.product_id = ch.product_id
  WHERE ch.categoria = 'PAGO'::text AND ch.valor_cobrado > 0::numeric
  ORDER BY ch.student_id, (COALESCE(ch.contract_id::text, ch.voomp_venda_id)), ch.data_pagamento;

GRANT SELECT ON unipds.v_matriculas_ativas TO anon, authenticated, service_role;

-- 4c. vw_inadimplencia (grao parcela -> helper por contrato)
CREATE OR REPLACE VIEW unipds.vw_inadimplencia AS
 WITH parcelas_devidas AS (
         SELECT vt.contract_id,
            vt.tenant_id,
            vt.student_id,
            vt.product_id,
            vt.voomp_contrato_id,
            vt.numero_parcela,
            vt.data_prevista,
            vt.valor_parcela_previsto,
            vt.status_parcela,
            vt.charge_id,
            vt.voomp_venda_id,
            vt.data_vencimento_real,
            vt.dias_atraso_charge AS dias_atraso_voomp,
            vt.dias_atraso_teorico
           FROM unipds.vw_cronograma_teorico vt
          WHERE (vt.status_parcela = ANY (ARRAY['EM_ABERTO'::text, 'NAO_EMITIDA'::text])) AND vt.dias_atraso_teorico > 1
        )
 SELECT pd.contract_id,
    pd.tenant_id,
    pd.student_id,
    pd.product_id,
    pd.voomp_contrato_id,
    COALESCE(cmp.nome_comprador, s.nome) AS aluno_nome,
    s.cpf_cnpj AS aluno_cpf,
    COALESCE(cmp.email_comprador, s.email) AS aluno_email,
    p.nome AS produto_nome,
    pd.numero_parcela,
    pd.data_prevista,
    pd.data_vencimento_real,
    pd.valor_parcela_previsto,
    pd.status_parcela,
    pd.dias_atraso_voomp,
    pd.dias_atraso_teorico,
        CASE
            WHEN pd.dias_atraso_teorico >= 2 AND pd.dias_atraso_teorico <= 30 THEN '1_30D'::text
            WHEN pd.dias_atraso_teorico >= 31 AND pd.dias_atraso_teorico <= 60 THEN '31_60D'::text
            WHEN pd.dias_atraso_teorico >= 61 AND pd.dias_atraso_teorico <= 90 THEN '61_90D'::text
            WHEN pd.dias_atraso_teorico > 90 THEN '90PLUS'::text
            ELSE 'EM_DIA'::text
        END AS bucket_aging,
        CASE
            WHEN pd.status_parcela = 'EM_ABERTO'::text THEN 'VOOMP_EMITIU'::text
            WHEN pd.status_parcela = 'NAO_EMITIDA'::text THEN 'VOOMP_NAO_EMITIU'::text
            ELSE NULL::text
        END AS situacao_emissao
   FROM parcelas_devidas pd
     JOIN unipds.students s ON s.student_id = pd.student_id
     JOIN unipds.products p ON p.product_id = pd.product_id
     LEFT JOIN unipds.vw_contrato_comprador cmp ON cmp.contract_id = pd.contract_id;

GRANT SELECT ON unipds.vw_inadimplencia TO anon, authenticated, service_role;

-- 4d. faturamento.vw_contratos_risco_cancelamento (grao contrato -> helper)
CREATE OR REPLACE VIEW faturamento.vw_contratos_risco_cancelamento AS
 WITH parcelas AS (
         SELECT vpc.contract_id,
            vpc.tenant_id,
            vpc.voomp_contrato_id,
            vpc.status_contrato,
            vpc.recorrencia_total,
            vpc.numero_parcela,
            vpc.status_parcela,
            vpc.data_referencia,
            vpc.data_pagamento,
            vpc.valor_previsto
           FROM faturamento.vw_parcelas_contratuais vpc
          WHERE vpc.status_contrato <> 'Cancelado'::text
        ), metricas_contrato AS (
         SELECT parcelas.contract_id,
            parcelas.tenant_id,
            parcelas.voomp_contrato_id,
            parcelas.status_contrato,
            parcelas.recorrencia_total,
            count(*) FILTER (WHERE parcelas.status_parcela = 'PAGA'::text) AS parcelas_pagas,
            count(*) FILTER (WHERE parcelas.status_parcela = 'EM_ABERTO'::text AND parcelas.data_referencia < CURRENT_DATE) AS parcelas_vencidas_em_aberto,
            count(*) FILTER (WHERE parcelas.status_parcela = 'NAO_EMITIDA'::text) AS parcelas_nao_emitidas,
            max(parcelas.data_pagamento) AS ultimo_pagamento,
            min(parcelas.data_referencia) FILTER (WHERE parcelas.status_parcela = 'EM_ABERTO'::text AND parcelas.data_referencia < CURRENT_DATE) AS data_primeira_inadimplencia,
            sum(
                CASE
                    WHEN parcelas.status_parcela = 'EM_ABERTO'::text AND parcelas.data_referencia < CURRENT_DATE THEN parcelas.valor_previsto
                    WHEN parcelas.status_parcela = 'NAO_EMITIDA'::text THEN parcelas.valor_previsto
                    ELSE 0::numeric
                END) AS valor_em_risco,
            sum(
                CASE
                    WHEN parcelas.status_parcela = 'EM_ABERTO'::text AND parcelas.data_referencia < CURRENT_DATE THEN parcelas.valor_previsto
                    ELSE 0::numeric
                END) AS valor_vencido_aberto,
            sum(
                CASE
                    WHEN parcelas.status_parcela = 'NAO_EMITIDA'::text THEN parcelas.valor_previsto
                    ELSE 0::numeric
                END) AS valor_nao_emitido
           FROM parcelas
          GROUP BY parcelas.contract_id, parcelas.tenant_id, parcelas.voomp_contrato_id, parcelas.status_contrato, parcelas.recorrencia_total
        )
 SELECT mc.contract_id,
    mc.tenant_id,
    t.nome AS tenant_nome,
    mc.voomp_contrato_id,
    s.student_id,
    COALESCE(cmp.nome_comprador, s.nome) AS aluno_nome,
    s.cpf_cnpj,
    COALESCE(cmp.email_comprador, s.email) AS email,
    COALESCE(cmp.telefone_comprador, s.telefone) AS telefone,
    p.nome AS produto_nome,
    mc.status_contrato,
    mc.recorrencia_total,
    mc.parcelas_pagas,
    mc.parcelas_vencidas_em_aberto,
    mc.parcelas_nao_emitidas,
    mc.ultimo_pagamento,
    mc.data_primeira_inadimplencia,
        CASE
            WHEN mc.ultimo_pagamento IS NULL THEN NULL::integer
            ELSE CURRENT_DATE - mc.ultimo_pagamento
        END AS dias_desde_ultimo_pagamento,
        CASE
            WHEN mc.data_primeira_inadimplencia IS NULL THEN NULL::integer
            ELSE CURRENT_DATE - mc.data_primeira_inadimplencia
        END AS dias_em_inadimplencia,
    mc.valor_vencido_aberto,
    mc.valor_nao_emitido,
    mc.valor_em_risco,
        CASE
            WHEN mc.parcelas_vencidas_em_aberto >= 3 AND (CURRENT_DATE - COALESCE(mc.ultimo_pagamento, mc.data_primeira_inadimplencia)) >= 90 THEN 'ALTO'::text
            WHEN mc.parcelas_vencidas_em_aberto >= 2 AND (CURRENT_DATE - COALESCE(mc.ultimo_pagamento, mc.data_primeira_inadimplencia)) >= 60 THEN 'MEDIO'::text
            ELSE 'BAIXO'::text
        END AS score_risco
   FROM metricas_contrato mc
     JOIN unipds.contracts c ON c.contract_id = mc.contract_id
     JOIN unipds.students s ON s.student_id = c.student_id
     JOIN unipds.tenants t ON t.tenant_id = mc.tenant_id
     JOIN unipds.products p ON p.product_id = c.product_id
     LEFT JOIN unipds.vw_contrato_comprador cmp ON cmp.contract_id = mc.contract_id
  WHERE mc.parcelas_vencidas_em_aberto > 0;

GRANT SELECT ON faturamento.vw_contratos_risco_cancelamento TO anon, authenticated, service_role;

-- 4e. cobranca.vw_casos_cobranca (grao contrato -> helper) [territorio cobranca]
CREATE OR REPLACE VIEW cobranca.vw_casos_cobranca AS
 WITH inad AS (
         SELECT i.contract_id,
                CASE max(
                    CASE i.bucket_aging
                        WHEN '90PLUS'::text THEN 4
                        WHEN '61_90D'::text THEN 3
                        WHEN '31_60D'::text THEN 2
                        WHEN '1_30D'::text THEN 1
                        ELSE 0
                    END)
                    WHEN 4 THEN 'faixa_4'::text
                    WHEN 3 THEN 'faixa_3'::text
                    WHEN 2 THEN 'faixa_2'::text
                    ELSE 'faixa_1'::text
                END AS faixa_aging,
            count(i.numero_parcela) AS parcelas_vencidas,
            COALESCE(sum(i.valor_parcela_previsto), 0::numeric) AS valor_total_aberto,
            max(i.dias_atraso_voomp) AS max_dias_atraso
           FROM unipds.vw_inadimplencia i
          WHERE i.situacao_emissao = 'VOOMP_EMITIU'::text
          GROUP BY i.contract_id
        ), contatos AS (
         SELECT ci.caso_id,
            count(*) AS total_contatos,
            count(*) FILTER (WHERE ci.houve_retorno) AS total_retornos,
            max(ci.data_contato) AS data_ultimo_contato
           FROM cobranca.cobranca_interacoes ci
          GROUP BY ci.caso_id
        ), negociacao_ativa AS (
         SELECT DISTINCT ON (cobranca_negociacoes.caso_id) cobranca_negociacoes.caso_id,
            cobranca_negociacoes.status,
            cobranca_negociacoes.valor_total_acordado
           FROM cobranca.cobranca_negociacoes
          WHERE cobranca_negociacoes.status = 'em_andamento'::text
          ORDER BY cobranca_negociacoes.caso_id, cobranca_negociacoes.created_at DESC
        )
 SELECT c.contract_id,
    c.tenant_id,
    c.student_id,
    c.voomp_contrato_id,
    COALESCE(cmp.nome_comprador, s.nome) AS nome,
    s.cpf_cnpj,
    COALESCE(cmp.email_comprador, s.email) AS email,
    COALESCE(cmp.telefone_comprador, s.telefone) AS telefone,
    p.nome AS nome_produto,
    c.periodo AS classe,
    t.nome AS tenant_nome,
    c.status_contrato,
    c.recorrencia_total,
    c.data_primeira_venda,
    inad.faixa_aging,
    inad.parcelas_vencidas,
    inad.valor_total_aberto,
    inad.max_dias_atraso,
    cc.caso_id,
    COALESCE(cc.status, 'em_aberto'::text) AS status,
    cc.valor_revertido,
    cc.responsavel,
    cc.data_abertura,
    cc.data_ultima_interacao,
    cc.data_encerramento,
    COALESCE(ct.total_contatos, 0::bigint) AS total_contatos,
    COALESCE(ct.total_retornos, 0::bigint) AS total_retornos,
    ct.data_ultimo_contato,
    na.status AS status_negociacao,
    na.valor_total_acordado AS valor_negociado,
    vr.dias_caso_aberto,
    vr.dias_desde_ultimo_contato,
    vr.duracao_caso_dias,
    vr.valor_pago_apos_abertura,
    vr.parcelas_pagas_apos_abertura,
    vr.data_ultimo_pagamento,
    vr.parcelas_em_aberto_hoje,
    vr.candidato_para_fechar,
    vr.divergencia_analista_pago_voomp_aberto
   FROM unipds.contracts c
     JOIN unipds.students s ON s.student_id = c.student_id
     JOIN unipds.products p ON p.product_id = c.product_id
     JOIN unipds.tenants t ON t.tenant_id = c.tenant_id
     JOIN inad ON inad.contract_id = c.contract_id
     LEFT JOIN unipds.vw_contrato_comprador cmp ON cmp.contract_id = c.contract_id
     LEFT JOIN cobranca.cobranca_casos cc ON cc.contract_id = c.contract_id
     LEFT JOIN contatos ct ON ct.caso_id = cc.caso_id
     LEFT JOIN negociacao_ativa na ON na.caso_id = cc.caso_id
     LEFT JOIN cobranca.vw_casos_recuperacao vr ON vr.caso_id = cc.caso_id;

GRANT SELECT ON cobranca.vw_casos_cobranca TO anon, authenticated, service_role;

-- 4f. cobranca.vw_reversoes (grao contrato -> helper) [territorio cobranca]
CREATE OR REPLACE VIEW cobranca.vw_reversoes AS
 WITH interacoes_agg AS (
         SELECT ci.caso_id,
            min(ci.data_contato) AS data_primeira_interacao,
            max(ci.data_contato) AS data_ultima_interacao,
            count(*) AS total_interacoes,
            count(*) FILTER (WHERE ci.houve_retorno) AS interacoes_com_retorno
           FROM cobranca.cobranca_interacoes ci
          GROUP BY ci.caso_id
        ), trabalhados AS (
         SELECT cc.caso_id,
            cc.contract_id,
            cc.tenant_id,
            cc.status,
            cc.responsavel,
            cc.data_abertura,
            cc.valor_revertido AS valor_manual,
            ia.data_primeira_interacao,
            ia.data_ultima_interacao,
            COALESCE(ia.total_interacoes, 0::bigint) AS total_interacoes,
            COALESCE(ia.interacoes_com_retorno, 0::bigint) AS interacoes_com_retorno,
            ia.caso_id IS NOT NULL AS tem_interacao,
            COALESCE(ia.data_primeira_interacao, cc.data_abertura) AS corte
           FROM cobranca.cobranca_casos cc
             LEFT JOIN interacoes_agg ia ON ia.caso_id = cc.caso_id
          WHERE ia.caso_id IS NOT NULL OR cc.status <> 'em_aberto'::text OR cc.valor_revertido IS NOT NULL OR cc.responsavel IS NOT NULL
        ), pagos AS (
         SELECT t_1.caso_id,
            sum(ch.valor_cobrado) AS valor_auto,
            count(*) AS parcelas_pagas,
            max(ch.data_pagamento) AS data_ultimo_pagamento
           FROM trabalhados t_1
             JOIN unipds.charges ch ON ch.contract_id = t_1.contract_id AND ch.categoria = 'PAGO'::text AND ch.data_pagamento >= t_1.corte
          GROUP BY t_1.caso_id
        )
 SELECT t.caso_id,
    t.contract_id,
    t.tenant_id,
    tn.nome AS tenant_nome,
    c.voomp_contrato_id,
    s.student_id,
    COALESCE(cmp.nome_comprador, s.nome) AS aluno_nome,
    s.cpf_cnpj,
    COALESCE(cmp.email_comprador, s.email) AS email,
    COALESCE(cmp.telefone_comprador, s.telefone) AS telefone,
    p.nome AS produto_nome,
    t.status AS status_caso,
    t.responsavel,
    t.data_abertura,
    t.tem_interacao,
    t.total_interacoes,
    t.interacoes_com_retorno,
    t.data_primeira_interacao,
    t.data_ultima_interacao,
        CASE
            WHEN COALESCE(pg.valor_auto, 0::numeric) > 0::numeric THEN pg.valor_auto
            ELSE COALESCE(t.valor_manual, 0::numeric)
        END AS valor_revertido,
        CASE
            WHEN COALESCE(pg.valor_auto, 0::numeric) > 0::numeric THEN 'pagamento_detectado'::text
            WHEN COALESCE(t.valor_manual, 0::numeric) > 0::numeric THEN 'baixa_manual'::text
            ELSE 'sem_reversao'::text
        END AS origem_valor,
    COALESCE(pg.parcelas_pagas, 0::bigint) AS parcelas_pagas_pos_corte,
    pg.data_ultimo_pagamento AS data_ultimo_pagamento_pos_contato,
    t.valor_manual AS valor_revertido_manual_ref,
    COALESCE(pg.valor_auto, 0::numeric) AS valor_pago_detectado,
        CASE
            WHEN COALESCE(pg.valor_auto, 0::numeric) > 0::numeric THEN pg.valor_auto
            ELSE COALESCE(t.valor_manual, 0::numeric)
        END > 0::numeric AS houve_reversao
   FROM trabalhados t
     JOIN unipds.contracts c ON c.contract_id = t.contract_id
     JOIN unipds.students s ON s.student_id = c.student_id
     JOIN unipds.products p ON p.product_id = c.product_id
     JOIN unipds.tenants tn ON tn.tenant_id = t.tenant_id
     LEFT JOIN unipds.vw_contrato_comprador cmp ON cmp.contract_id = t.contract_id
     LEFT JOIN pagos pg ON pg.caso_id = t.caso_id;

GRANT SELECT ON cobranca.vw_reversoes TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
