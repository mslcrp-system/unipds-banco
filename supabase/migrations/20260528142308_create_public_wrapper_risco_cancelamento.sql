
CREATE OR REPLACE FUNCTION public.get_risco_cancelamento(p_tenant_id uuid DEFAULT NULL)
RETURNS TABLE(
  contract_id                  uuid,
  tenant_id                    uuid,
  tenant_nome                  text,
  voomp_contrato_id            text,
  student_id                   uuid,
  aluno_nome                   text,
  cpf_cnpj                     text,
  email                        text,
  telefone                     text,
  produto_nome                 text,
  status_contrato              text,
  recorrencia_total            integer,
  parcelas_pagas               bigint,
  parcelas_vencidas_em_aberto  bigint,
  parcelas_nao_emitidas        bigint,
  ultimo_pagamento             date,
  data_primeira_inadimplencia  date,
  dias_desde_ultimo_pagamento  integer,
  dias_em_inadimplencia        integer,
  valor_vencido_aberto         numeric,
  valor_nao_emitido            numeric,
  valor_em_risco               numeric,
  score_risco                  text
)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    contract_id, tenant_id, tenant_nome, voomp_contrato_id, student_id,
    aluno_nome, cpf_cnpj, email, telefone, produto_nome, status_contrato,
    recorrencia_total, parcelas_pagas, parcelas_vencidas_em_aberto,
    parcelas_nao_emitidas, ultimo_pagamento, data_primeira_inadimplencia,
    dias_desde_ultimo_pagamento, dias_em_inadimplencia,
    valor_vencido_aberto, valor_nao_emitido, valor_em_risco, score_risco
  FROM faturamento.vw_contratos_risco_cancelamento
  WHERE p_tenant_id IS NULL OR tenant_id = p_tenant_id
  ORDER BY
    CASE score_risco WHEN 'ALTO' THEN 1 WHEN 'MEDIO' THEN 2 ELSE 3 END,
    valor_em_risco DESC;
$$;

GRANT EXECUTE ON FUNCTION public.get_risco_cancelamento(uuid) TO anon, authenticated;
