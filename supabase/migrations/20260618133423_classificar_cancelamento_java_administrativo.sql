-- ============================================================
-- v_produtos_classificados: produto 15428 (Cancelamento Pós Java)
-- como ADMINISTRATIVO.
--
-- Surgiu no XLSX de 18/06 o produto "Cancelamento Pós: Pós-Graduação
-- Java Elite" (voomp_produto_id 15428, Java), classificado como OUTRO.
-- Eh cancelamento — mesma natureza de multas/negociacoes, NAO eh
-- venda. Decisao do dono (18/06): manter no mesmo pacote
-- ADMINISTRATIVO, fora de vendas/conciliacao.
-- ============================================================

CREATE OR REPLACE VIEW unipds.v_produtos_classificados AS
SELECT product_id,
    voomp_produto_id,
    nome,
    tipo,
    CASE
        WHEN voomp_produto_id = ANY (ARRAY['7724','7852','13761','13762','12663']) THEN 'POS_GRADUACAO'
        WHEN voomp_produto_id = ANY (ARRAY['7725','7856']) THEN 'EXTENSAO'
        WHEN voomp_produto_id = ANY (ARRAY['9752','12228','10908']) THEN 'ADMINISTRATIVO'
        WHEN voomp_produto_id = ANY (ARRAY['11957','11971','12657','12658','12882','13459','13764','13766']) THEN 'POS_GRADUACAO'
        WHEN voomp_produto_id = ANY (ARRAY['11973','11974','13497','14164']) THEN 'EXTENSAO'
        WHEN voomp_produto_id = ANY (ARRAY['11972','12229','15428']) THEN 'ADMINISTRATIVO'
        ELSE 'OUTRO'
    END AS classe
FROM unipds.products;

GRANT SELECT ON unipds.v_produtos_classificados TO anon, authenticated, service_role;
