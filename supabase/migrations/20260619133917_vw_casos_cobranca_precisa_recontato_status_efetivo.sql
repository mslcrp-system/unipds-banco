-- ============================================================
-- vw_casos_cobranca: flag precisa_recontato + status_efetivo
--
-- PROBLEMA (validado com o caso do Caio César, contrato 149509 Java):
-- o caso de cobranca tem grao de CONTRATO (1 linha por contract_id) e
-- as interacoes (cobranca_interacoes) sao amarradas ao caso, nunca a
-- parcela. Entao quando o aluno paga a parcela que gerou o contato e
-- DEPOIS fura uma parcela nova, o caso continua 'em_contato' carregando
-- o contato antigo — ele NAO volta pra fila de novos contatos, fica
-- mascarado como "ja contatado" mesmo sem ninguem ter acionado a divida
-- atual. Ex.: contato em 21/05 (sobre a P4, ja paga em 25/05); P5 vence
-- 04/06 e fica 15d em atraso sem recontato.
--
-- SOLUCAO (opcao A, aditiva, view-only, reversivel — sem tocar dados):
-- duas colunas novas no FIM da view (zero regressao no front atual):
--
--   precisa_recontato (boolean):
--     TRUE quando existe parcela vencida (conjunto VOOMP_EMITIU que a
--     view ja usa) cujo vencimento e POSTERIOR ao ultimo contato real.
--     Usa o ultimo contato CALCULADO de cobranca_interacoes
--     (ct.data_ultimo_contato = max(data_contato)), NAO a coluna
--     cobranca_casos.data_ultima_interacao, que hoje nao e mantida
--     (esta NULL inclusive no caso do Caio — usar ela faria a flag
--     nunca disparar).
--
--   status_efetivo (text):
--     status do ciclo atual. Quando precisa_recontato e o caso nao esta
--     em acordo ativo, rebaixa para 'em_aberto' (repesca pra fila de
--     novos contatos). 'acordo_ativo' e preservado para nao puxar uma
--     negociacao vigente de volta pra fila. Casos sem caso seguem
--     'em_aberto'; 'pago' que reabriu (tem parcela vencida nova) tambem
--     volta a 'em_aberto'.
--
-- CONTRATO PRO FRONT (repo Cobranca):
--   - filtros passam a usar status_efetivo no lugar de status;
--   - badge "novo ciclo" quando precisa_recontato = true;
--   - 'status' original permanece inalterado (compat).
-- ============================================================

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
            max(i.dias_atraso_voomp) AS max_dias_atraso,
            max(COALESCE(i.data_vencimento_real, i.data_prevista)) AS max_venc_vencida
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
    vr.divergencia_analista_pago_voomp_aberto,
    -- NOVO: divida vencida posterior ao ultimo contato real
    (ct.data_ultimo_contato IS NOT NULL
        AND inad.max_venc_vencida > ct.data_ultimo_contato) AS precisa_recontato,
    -- NOVO: status do ciclo atual (repesca recontato; preserva acordo)
    CASE
        WHEN ct.data_ultimo_contato IS NOT NULL
            AND inad.max_venc_vencida > ct.data_ultimo_contato
            AND COALESCE(cc.status, 'em_aberto'::text) <> 'acordo_ativo'::text
        THEN 'em_aberto'::text
        ELSE COALESCE(cc.status, 'em_aberto'::text)
    END AS status_efetivo
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

NOTIFY pgrst, 'reload schema';
