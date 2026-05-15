CREATE OR REPLACE VIEW cobranca.v_casos_completos AS
SELECT
    cc.caso_id,
    cc.contract_id,
    cc.tenant_id,
    CASE
        WHEN cc.tenant_id = '70b668e4-be85-459b-8dbb-3876929ac850'::uuid THEN 'Java'::text
        WHEN cc.tenant_id = 'e717e24d-fb30-4ed0-83d3-bb8ea0b66783'::uuid THEN 'IA'::text
        ELSE NULL::text
    END AS tenant_nome,
    cc.status,
    cc.faixa_aging,
    cc.valor_total_aberto,
    cc.parcelas_vencidas,
    cc.valor_revertido,
    cc.data_pagamento_revertido,
    cc.responsavel,
    cc.data_abertura,
    cc.data_ultima_interacao,
    cc.data_encerramento,
    cc.observacao_encerramento,
    c.contract_ref,
    c.voomp_contrato_id,
    c.status_contrato,
    c.tipo_cobranca,
    s.nome,
    s.cpf_cnpj,
    s.email,
    s.telefone,
    ( SELECT count(*)
           FROM cobranca.cobranca_interacoes ci
          WHERE ci.caso_id = cc.caso_id) AS total_contatos,
    ( SELECT count(*)
           FROM cobranca.cobranca_interacoes ci
          WHERE ci.caso_id = cc.caso_id AND ci.houve_retorno = true) AS total_retornos,
    ( SELECT max(ci.data_contato)
           FROM cobranca.cobranca_interacoes ci
          WHERE ci.caso_id = cc.caso_id) AS data_ultimo_contato,
    ( SELECT cn.status
           FROM cobranca.cobranca_negociacoes cn
          WHERE cn.caso_id = cc.caso_id
          ORDER BY cn.created_at DESC
         LIMIT 1) AS status_negociacao,
    ( SELECT cn.valor_total_acordado
           FROM cobranca.cobranca_negociacoes cn
          WHERE cn.caso_id = cc.caso_id
          ORDER BY cn.created_at DESC
         LIMIT 1) AS valor_negociado,
    ( SELECT cn.data_primeiro_vencimento
           FROM cobranca.cobranca_negociacoes cn
          WHERE cn.caso_id = cc.caso_id
          ORDER BY cn.created_at DESC
         LIMIT 1) AS proximo_vencimento_acordo,
    p.nome AS nome_produto,
    p.classe
FROM cobranca.cobranca_casos cc
    JOIN unipds.contracts c ON c.contract_id = cc.contract_id
    JOIN unipds.students s ON s.student_id = c.student_id
    LEFT JOIN unipds.v_produtos_classificados p ON p.product_id = c.product_id
ORDER BY cc.faixa_aging DESC, cc.valor_total_aberto DESC;
