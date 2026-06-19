-- ============================================================
-- v_produtos_classificados: + coluna `curso` (nome canonico) e
-- reclassifica os produtos "Empresa" que estavam em OUTRO.
--
-- 1) RECLASSIFICACAO: 14165 ("Extensão Engenharia de IA Aplicada -
--    Empresa") e 14168 ("Extensão Universitária Java Elite - A VISTA -
--    Empresa") estavam em OUTRO. Sao extensao real (variante corporativa)
--    -> EXTENSAO.
--
-- 2) NOME CANONICO `curso`: o nome do XLSX carrega variantes comerciais
--    (- A VISTA, - Empresa, - Recorrente, - vlr único) e ate grafias
--    diferentes ("Pós graduação - Java Elite" vs "Pós-Graduação Java
--    Elite"). split_part(' - ') nao serve (cortaria "Java Elite").
--    Solucao: nome canonico por classe + palavra-chave (Java Elite /
--    IA Aplicada), unificando todas as variantes nos 4 cursos reais.
--    Foca so no nome do curso (sem "Empresa").
-- ============================================================

CREATE OR REPLACE VIEW unipds.v_produtos_classificados AS
SELECT q.product_id,
       q.voomp_produto_id,
       q.nome,
       q.tipo,
       q.classe,
       CASE
           WHEN q.classe = 'POS_GRADUACAO' AND q.nome ILIKE '%Java Elite%'  THEN 'Pós-Graduação Java Elite'
           WHEN q.classe = 'POS_GRADUACAO' AND q.nome ILIKE '%IA Aplicada%' THEN 'Pós-Graduação Engenharia de IA Aplicada'
           WHEN q.classe = 'EXTENSAO'      AND q.nome ILIKE '%Java Elite%'  THEN 'Extensão Universitária Java Elite'
           WHEN q.classe = 'EXTENSAO'      AND q.nome ILIKE '%IA Aplicada%' THEN 'Extensão Engenharia de IA Aplicada'
           WHEN q.classe = 'ADMINISTRATIVO' THEN trim(regexp_replace(q.nome, '\s*-\s*vlr único\s*$', '', 'i'))
           ELSE q.nome
       END AS curso
FROM (
    SELECT product_id,
        voomp_produto_id,
        nome,
        tipo,
        CASE
            WHEN voomp_produto_id = ANY (ARRAY['7724','7852','13761','13762','12663']) THEN 'POS_GRADUACAO'
            WHEN voomp_produto_id = ANY (ARRAY['7725','7856']) THEN 'EXTENSAO'
            WHEN voomp_produto_id = ANY (ARRAY['9752','12228','10908']) THEN 'ADMINISTRATIVO'
            WHEN voomp_produto_id = ANY (ARRAY['11957','11971','12657','12658','12882','13459','13764','13766']) THEN 'POS_GRADUACAO'
            WHEN voomp_produto_id = ANY (ARRAY['11973','11974','13497','14164','14165','14168']) THEN 'EXTENSAO'
            WHEN voomp_produto_id = ANY (ARRAY['11972','12229','15428']) THEN 'ADMINISTRATIVO'
            ELSE 'OUTRO'
        END AS classe
    FROM unipds.products
) q;

GRANT SELECT ON unipds.v_produtos_classificados TO anon, authenticated, service_role;
