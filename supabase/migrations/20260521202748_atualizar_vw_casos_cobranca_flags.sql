-- ============================================================
-- Atualiza cobranca.vw_casos_cobranca
--
-- Adiciona colunas de tempo do caso, recuperacao financeira e
-- flags de divergencia/sugestao, todas vindas de vw_casos_recuperacao.
--
-- CREATE OR REPLACE VIEW so aceita novas colunas no FINAL do SELECT
-- (licao aprendida da migration 20260517211946). Por isso a
-- definicao atual da view eh reproduzida integralmente e as
-- colunas novas sao acrescentadas no final.
--
-- A view continua com a mesma logica de JOIN com vw_inadimplencia
-- filtrando situacao_emissao = 'VOOMP_EMITIU'. As novas colunas
-- vem de um LEFT JOIN com vw_casos_recuperacao.
-- ============================================================

CREATE OR REPLACE VIEW cobranca.vw_casos_cobranca AS
SELECT
    c.contract_id,
    c.tenant_id,
    c.student_id,
    c.voomp_contrato_id,
    s.nome,
    s.cpf_cnpj,
    s.email,
    s.telefone,
    p.nome AS nome_produto,
    c.periodo AS classe,
    t.nome AS tenant_nome,
    c.status_contrato,
    c.recorrencia_total,
    c.data_primeira_venda,
    CASE i.bucket_aging
        WHEN '1_30D'  THEN 'faixa_1'
        WHEN '31_60D' THEN 'faixa_2'
        WHEN '61_90D' THEN 'faixa_3'
        WHEN '90PLUS' THEN 'faixa_4'
        ELSE 'faixa_1'
    END AS faixa_aging,
    count(i.numero_parcela)                                 AS parcelas_vencidas,
    COALESCE(sum(i.valor_parcela_previsto), 0::numeric)     AS valor_total_aberto,
    max(i.dias_atraso_voomp)                                AS max_dias_atraso,
    cc.caso_id,
    COALESCE(cc.status, 'em_aberto'::text)                  AS status,
    cc.valor_revertido,
    cc.responsavel,
    cc.data_abertura,
    cc.data_ultima_interacao,
    cc.data_encerramento,
    count(ci.interacao_id)                                  AS total_contatos,
    count(ci.interacao_id) FILTER (WHERE ci.houve_retorno)  AS total_retornos,
    max(ci.data_contato)                                    AS data_ultimo_contato,
    cn.status                                               AS status_negociacao,
    cn.valor_total_acordado                                 AS valor_negociado,

    -- ── Colunas novas (adicionadas via LEFT JOIN com vw_casos_recuperacao) ──
    -- Tempo do caso (operacional)
    vr.dias_caso_aberto,
    vr.dias_desde_ultimo_contato,
    vr.duracao_caso_dias,
    -- Verdade financeira pos-abertura
    vr.valor_pago_apos_abertura,
    vr.parcelas_pagas_apos_abertura,
    vr.data_ultimo_pagamento,
    vr.parcelas_em_aberto_hoje,
    -- Flags
    vr.candidato_para_fechar,
    vr.divergencia_analista_pago_voomp_aberto

FROM unipds.contracts c
JOIN unipds.students s ON s.student_id = c.student_id
JOIN unipds.products p ON p.product_id = c.product_id
JOIN unipds.tenants  t ON t.tenant_id  = c.tenant_id
JOIN unipds.vw_inadimplencia i
    ON i.contract_id = c.contract_id
   AND i.situacao_emissao = 'VOOMP_EMITIU'
LEFT JOIN cobranca.cobranca_casos       cc ON cc.contract_id = c.contract_id
LEFT JOIN cobranca.cobranca_interacoes  ci ON ci.caso_id     = cc.caso_id
LEFT JOIN cobranca.cobranca_negociacoes cn ON cn.caso_id     = cc.caso_id
                                          AND cn.status      = 'em_andamento'
LEFT JOIN cobranca.vw_casos_recuperacao vr ON vr.caso_id     = cc.caso_id
GROUP BY
    c.contract_id, c.tenant_id, c.student_id, c.voomp_contrato_id,
    s.nome, s.cpf_cnpj, s.email, s.telefone,
    p.nome, c.periodo, t.nome,
    c.status_contrato, c.recorrencia_total, c.data_primeira_venda,
    i.bucket_aging,
    cc.caso_id, cc.status, cc.valor_revertido, cc.responsavel,
    cc.data_abertura, cc.data_ultima_interacao, cc.data_encerramento,
    cn.status, cn.valor_total_acordado,
    vr.dias_caso_aberto, vr.dias_desde_ultimo_contato, vr.duracao_caso_dias,
    vr.valor_pago_apos_abertura, vr.parcelas_pagas_apos_abertura,
    vr.data_ultimo_pagamento, vr.parcelas_em_aberto_hoje,
    vr.candidato_para_fechar, vr.divergencia_analista_pago_voomp_aberto;

COMMENT ON VIEW cobranca.vw_casos_cobranca IS
  'View principal do dashboard de cobranca. Une contratos inadimplentes (VOOMP_EMITIU) com casos manuais, interacoes, negociacoes e flags de recuperacao/divergencia vindas de vw_casos_recuperacao.';
