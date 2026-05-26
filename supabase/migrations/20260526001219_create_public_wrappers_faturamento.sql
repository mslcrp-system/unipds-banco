
CREATE OR REPLACE FUNCTION public.get_faturamento_mensal(p_tenant_id uuid DEFAULT NULL)
RETURNS TABLE(
  mes text, status_mes text,
  esperado numeric, realizado numeric,
  inadimplente numeric, reembolsado numeric, saldo_aberto numeric
)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT * FROM faturamento.get_faturamento_mensal(p_tenant_id);
$$;

CREATE OR REPLACE FUNCTION public.get_faturamento_por_tenant(p_tenant_id uuid DEFAULT NULL)
RETURNS TABLE(
  mes text, tenant_id uuid, tenant_nome text, status_mes text,
  esperado numeric, realizado numeric,
  inadimplente numeric, reembolsado numeric, saldo_aberto numeric
)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT * FROM faturamento.get_faturamento_por_tenant(p_tenant_id);
$$;

CREATE OR REPLACE FUNCTION public.get_cohort_faturamento(p_tenant_id uuid DEFAULT NULL)
RETURNS TABLE(mes_entrada text, mes_recebido text, receita numeric, contratos bigint)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT * FROM faturamento.get_cohort_faturamento(p_tenant_id);
$$;

GRANT EXECUTE ON FUNCTION public.get_faturamento_mensal(uuid)     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_faturamento_por_tenant(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_cohort_faturamento(uuid)     TO anon, authenticated;
