-- ============================================================
-- Fix vw_casos_cobranca: evitar multiplicacao cartesiana
--
-- Problema:
--   A view agregava (COUNT, SUM, MAX) sobre o cruzamento direto
--   de vw_inadimplencia x cobranca_interacoes x cobranca_negociacoes.
--   Quando um caso tinha N interacoes registradas, cada parcela de
--   inadimplencia era duplicada N vezes, inflando parcelas_vencidas
--   e valor_total_aberto.
--
--   Exemplo real (contrato 139583, Atila Andreatti):
--     Realidade   : 1 parcela vencida (P6), R$ 500
--     Interacoes  : 3 contatos registrados
--     View antes  : parcelas_vencidas = 3, valor_total_aberto = 1500
--     View depois : parcelas_vencidas = 1, valor_total_aberto = 500
--
-- Correcao:
--   Pre-agregar cada fonte de forma isolada via CTEs (inad por
--   contract_id, contatos por caso_id, negociacao_ativa por caso_id)
--   e fazer JOIN com os agregados ja calculados. Cada fonte deixa
--   de afetar a contagem das outras.
--
-- Compatibilidade:
--   - Mesma ordem, nomes e tipos de coluna da view atual
--   - Sem mudanca para o front (cobranca consome via PostgREST)
-- ============================================================

CREATE OR REPLACE VIEW cobranca.vw_casos_cobranca AS
WITH inad AS (
    -- Agrega inadimplencia por contrato (VOOMP_EMITIU apenas)
    SELECT
        i.contract_id,
        -- Pior bucket entre as parcelas do contrato
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
        END                                                  AS faixa_aging,
        COUNT(i.numero_parcela)                              AS parcelas_vencidas,
        COALESCE(SUM(i.valor_parcela_previsto), 0::numeric)  AS valor_total_aberto,
        MAX(i.dias_atraso_voomp)                             AS max_dias_atraso
    FROM unipds.vw_inadimplencia i
    WHERE i.situacao_emissao = 'VOOMP_EMITIU'
    GROUP BY i.contract_id
),
contatos AS (
    -- Agrega interacoes por caso (separado, sem multiplicar parcelas)
    SELECT
        ci.caso_id,
        COUNT(*)                                          AS total_contatos,
        COUNT(*) FILTER (WHERE ci.houve_retorno)          AS total_retornos,
        MAX(ci.data_contato)                              AS data_ultimo_contato
    FROM cobranca.cobranca_interacoes ci
    GROUP BY ci.caso_id
),
negociacao_ativa AS (
    -- Garante 1 negociacao em_andamento por caso (caso houver duplicidade)
    SELECT DISTINCT ON (caso_id)
        caso_id,
        status,
        valor_total_acordado
    FROM cobranca.cobranca_negociacoes
    WHERE status = 'em_andamento'
    ORDER BY caso_id, created_at DESC
)
SELECT
    c.contract_id,
    c.tenant_id,
    c.student_id,
    c.voomp_contrato_id,
    s.nome,
    s.cpf_cnpj,
    s.email,
    s.telefone,
    p.nome                              AS nome_produto,
    c.periodo                           AS classe,
    t.nome                              AS tenant_nome,
    c.status_contrato,
    c.recorrencia_total,
    c.data_primeira_venda,
    inad.faixa_aging,
    inad.parcelas_vencidas,
    inad.valor_total_aberto,
    inad.max_dias_atraso,
    cc.caso_id,
    COALESCE(cc.status, 'em_aberto')    AS status,
    cc.valor_revertido,
    cc.responsavel,
    cc.data_abertura,
    cc.data_ultima_interacao,
    cc.data_encerramento,
    COALESCE(ct.total_contatos, 0)      AS total_contatos,
    COALESCE(ct.total_retornos, 0)      AS total_retornos,
    ct.data_ultimo_contato,
    na.status                           AS status_negociacao,
    na.valor_total_acordado             AS valor_negociado,

    -- Colunas vindas de vw_casos_recuperacao (mantidas)
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
JOIN unipds.tenants  t ON t.tenant_id  = c.tenant_id
JOIN inad ON inad.contract_id = c.contract_id
LEFT JOIN cobranca.cobranca_casos       cc ON cc.contract_id = c.contract_id
LEFT JOIN contatos                       ct ON ct.caso_id      = cc.caso_id
LEFT JOIN negociacao_ativa               na ON na.caso_id      = cc.caso_id
LEFT JOIN cobranca.vw_casos_recuperacao  vr ON vr.caso_id      = cc.caso_id;

COMMENT ON VIEW cobranca.vw_casos_cobranca IS
  'View principal do dashboard de cobranca. Pre-agrega inadimplencia, contatos e negociacoes por chave proprio antes do JOIN, evitando multiplicacao cartesiana.';
