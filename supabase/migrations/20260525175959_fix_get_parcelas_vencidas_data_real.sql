-- ============================================================
-- Fix public.get_parcelas_vencidas(uuid)
--
-- Problema:
--   A funcao retornava ct.data_prevista (cronograma teorico
--   matematico). Quando a Voomp emite o boleto em data diferente
--   da projetada, o front exibia o vencimento teorico em vez do
--   real - ex: Mariana P4 mostrava "15/06" (teorico) quando o
--   boleto real venceu em 23/05.
--
-- Correcao:
--   Trocar a expressao por COALESCE(data_vencimento_real, data_prevista).
--   - Voomp emitiu boleto -> retorna data_vencimento_real (verdade)
--   - Voomp NAO emitiu (NAO_EMITIDA) -> retorna data_prevista (fragilidade)
--
-- Compatibilidade:
--   - Mesma assinatura (mesmos parametros e tipo de retorno)
--   - Mesmo nome de coluna no retorno (data_prevista)
--   - Front nao precisa de mudanca alguma
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_parcelas_vencidas(p_contract_id uuid)
RETURNS TABLE (
  previsao_id      uuid,
  previsao_ref     text,
  numero_parcela   integer,
  total_parcelas   integer,
  valor_previsto   numeric,
  data_prevista    date,
  status           text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'unipds'
AS $$
  SELECT
    COALESCE(ct.charge_id, gen_random_uuid())              AS previsao_id,
    ct.voomp_contrato_id                                    AS previsao_ref,
    ct.numero_parcela,
    ct.recorrencia_total                                    AS total_parcelas,
    ct.valor_parcela_previsto                               AS valor_previsto,
    -- Verdade Voomp primeiro; teorico so como fallback (NAO_EMITIDA)
    COALESCE(ct.data_vencimento_real, ct.data_prevista)     AS data_prevista,
    ct.status_parcela                                       AS status
  FROM unipds.vw_cronograma_teorico ct
  WHERE ct.contract_id = p_contract_id
    AND ct.status_parcela IN ('VENCIDO', 'EM_ABERTO')
    AND ct.dias_atraso_teorico > 0
  ORDER BY COALESCE(ct.data_vencimento_real, ct.data_prevista) ASC;
$$;

GRANT EXECUTE ON FUNCTION public.get_parcelas_vencidas(uuid) TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_parcelas_vencidas(uuid) IS
  'Retorna parcelas em aberto/vencidas de um contrato. Coluna data_prevista carrega a data REAL do boleto (data_vencimento_real) quando a Voomp emitiu; cai para data_prevista (teorica) apenas em parcelas NAO_EMITIDA.';
