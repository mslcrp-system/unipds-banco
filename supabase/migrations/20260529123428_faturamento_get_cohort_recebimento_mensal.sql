-- ============================================================
-- Funcao faturamento.get_cohort_recebimento_mensal(p_ano_mes)
--
-- Cohort de recebimentos de ASSINATURA numa competencia (mes),
-- referente a contratos iniciados em meses ANTERIORES (recorrencia
-- pura — exclui vendas do proprio mes).
--
-- Quebra por mes de entrada do contrato (data_primeira_venda) x
-- 4 segmentos: IA Pos, IA Extensao, Java Pos, Java Extensao.
--
-- Escala BRUTA (valor_cobrado).
--
-- Classificacao de curso pelo NOME do produto (o campo tipo do
-- cadastro eh inconsistente):
--   - '%extens%'           -> Extensao
--   - '%pos%' / '%pós%'    -> Pos
--   - resto               -> Outros
--
-- Parametro:
--   p_ano_mes text 'YYYY-MM' (default = mes corrente)
--
-- Retorna 1 linha por mes_entrada + 1 linha TOTAL (mes_entrada='TOTAL').
-- ============================================================

CREATE OR REPLACE FUNCTION faturamento.get_cohort_recebimento_mensal(
    p_ano_mes text DEFAULT to_char(CURRENT_DATE, 'YYYY-MM')
)
RETURNS TABLE(
    mes_entrada    text,
    ia_pos         numeric,
    ia_extensao    numeric,
    java_pos       numeric,
    java_extensao  numeric,
    outros         numeric,
    total_mes      numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'faturamento','unipds','public'
AS $function$
DECLARE
    v_inicio date := (p_ano_mes || '-01')::date;
    v_fim    date := (p_ano_mes || '-01')::date + INTERVAL '1 month';
BEGIN
    RETURN QUERY
    WITH recebimentos AS (
        SELECT
            to_char(co.data_primeira_venda, 'YYYY-MM') AS m_entrada,
            CASE ch.tenant_id
                WHEN 'e717e24d-fb30-4ed0-83d3-bb8ea0b66783' THEN 'IA'
                WHEN '70b668e4-be85-459b-8dbb-3876929ac850' THEN 'Java'
                ELSE 'Outro'
            END AS empresa,
            CASE
                WHEN p.nome ILIKE '%extens%'                      THEN 'Extensao'
                WHEN p.nome ILIKE '%pós%' OR p.nome ILIKE '%pos%' THEN 'Pos'
                ELSE 'Outros'
            END AS tipo_curso,
            ch.valor_cobrado
        FROM unipds.charges ch
        JOIN unipds.contracts co ON co.contract_id = ch.contract_id
        JOIN unipds.products  p  ON p.product_id   = co.product_id
        WHERE ch.tipo_cobranca = 'Assinatura'
          AND ch.categoria = 'PAGO'
          AND ch.data_pagamento >= v_inicio
          AND ch.data_pagamento <  v_fim
          AND co.data_primeira_venda < v_inicio   -- so meses anteriores
    ),
    agregado AS (
        SELECT
            r.m_entrada,
            SUM(r.valor_cobrado) FILTER (WHERE r.empresa='IA'   AND r.tipo_curso='Pos')      AS ia_pos,
            SUM(r.valor_cobrado) FILTER (WHERE r.empresa='IA'   AND r.tipo_curso='Extensao') AS ia_extensao,
            SUM(r.valor_cobrado) FILTER (WHERE r.empresa='Java' AND r.tipo_curso='Pos')      AS java_pos,
            SUM(r.valor_cobrado) FILTER (WHERE r.empresa='Java' AND r.tipo_curso='Extensao') AS java_extensao,
            SUM(r.valor_cobrado) FILTER (WHERE r.tipo_curso='Outros'
                                            OR r.empresa='Outro')                            AS outros,
            SUM(r.valor_cobrado)                                                             AS total_mes
        FROM recebimentos r
        GROUP BY r.m_entrada
    )
    SELECT
        COALESCE(a.m_entrada, 'TOTAL')              AS mes_entrada,
        COALESCE(SUM(a.ia_pos), 0)                  AS ia_pos,
        COALESCE(SUM(a.ia_extensao), 0)             AS ia_extensao,
        COALESCE(SUM(a.java_pos), 0)                AS java_pos,
        COALESCE(SUM(a.java_extensao), 0)           AS java_extensao,
        COALESCE(SUM(a.outros), 0)                  AS outros,
        COALESCE(SUM(a.total_mes), 0)               AS total_mes
    FROM agregado a
    GROUP BY ROLLUP(a.m_entrada)
    ORDER BY (a.m_entrada IS NULL), a.m_entrada;  -- TOTAL por ultimo
END;
$function$;

COMMENT ON FUNCTION faturamento.get_cohort_recebimento_mensal(text) IS
  'Cohort de recebimentos de assinatura numa competencia (p_ano_mes YYYY-MM), de contratos de meses anteriores. Quebra por mes de entrada x IA/Java x Pos/Extensao. Escala bruta. Linha TOTAL ao final.';

GRANT EXECUTE ON FUNCTION faturamento.get_cohort_recebimento_mensal(text)
    TO anon, authenticated, service_role;

-- Wrapper em public para chamada simples via supabase.rpc()
CREATE OR REPLACE FUNCTION public.get_cohort_recebimento_mensal(
    p_ano_mes text DEFAULT to_char(CURRENT_DATE, 'YYYY-MM')
)
RETURNS TABLE(
    mes_entrada    text,
    ia_pos         numeric,
    ia_extensao    numeric,
    java_pos       numeric,
    java_extensao  numeric,
    outros         numeric,
    total_mes      numeric
)
LANGUAGE sql
SECURITY DEFINER AS $$
    SELECT * FROM faturamento.get_cohort_recebimento_mensal(p_ano_mes);
$$;

GRANT EXECUTE ON FUNCTION public.get_cohort_recebimento_mensal(text)
    TO anon, authenticated, service_role;
