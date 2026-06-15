-- ============================================================
-- RPC get_vencimentos_proximos — fila de PREVENCAO de inadimplencia
--
-- Lista nominal das parcelas EM_ABERTO que VENCEM nos proximos
-- p_dias dias (ainda nao vencidas), para o time de cobranca acionar
-- o aluno ANTES do vencimento e estancar a inadimplencia na origem.
--
-- Puramente ADITIVA: funcao nova, nao altera nada que o dashboard
-- de cobranca ja consome. O front so se pluga nela quando o dono
-- decidir (por hora, gera listas sob demanda).
--
-- Universo: mesma base do pacote CR (faturamento.vw_parcelas_
-- contratuais — carteira de assinatura, valor bruto). Aqui o recorte
-- e o OPOSTO do inadimplente: parcelas a vencer (data_referencia
-- entre hoje e hoje+p_dias).
--
-- p_dias default 7 (janela operacional que se renova toda semana).
-- p_tenant_id opcional: NULL = ambos os tenants.
-- Ordenado por data de vencimento (mais urgente primeiro).
-- ============================================================

CREATE OR REPLACE FUNCTION faturamento.get_vencimentos_proximos(
    p_dias      integer DEFAULT 7,
    p_tenant_id uuid    DEFAULT NULL
)
RETURNS TABLE(
    tenant            text,
    tenant_id         uuid,
    aluno             text,
    cpf_cnpj          text,
    telefone          text,
    email             text,
    produto           text,
    numero_parcela    integer,
    data_vencimento   date,
    dias_ate_vencer   integer,
    valor             numeric,
    voomp_contrato_id text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'faturamento','unipds','public'
SET statement_timeout TO '60s'
AS $$
  SELECT
    t.nome                                        AS tenant,
    t.tenant_id,
    s.nome                                        AS aluno,
    s.cpf_cnpj,
    s.telefone,
    s.email,
    p.nome                                        AS produto,
    vpc.numero_parcela,
    vpc.data_referencia                           AS data_vencimento,
    (vpc.data_referencia - CURRENT_DATE)          AS dias_ate_vencer,
    vpc.valor_previsto                            AS valor,
    vpc.voomp_contrato_id
  FROM faturamento.vw_parcelas_contratuais vpc
  JOIN unipds.tenants  t ON t.tenant_id  = vpc.tenant_id
  JOIN unipds.students s ON s.student_id = vpc.student_id
  LEFT JOIN unipds.products p ON p.product_id = vpc.product_id
  WHERE vpc.status_parcela = 'EM_ABERTO'
    AND vpc.data_referencia >= CURRENT_DATE
    AND vpc.data_referencia <= CURRENT_DATE + p_dias
    AND (p_tenant_id IS NULL OR vpc.tenant_id = p_tenant_id)
  ORDER BY vpc.data_referencia, t.nome, s.nome;
$$;

COMMENT ON FUNCTION faturamento.get_vencimentos_proximos(integer, uuid) IS
  'Fila de prevencao: parcelas de assinatura EM_ABERTO que vencem nos proximos p_dias (default 7), com contato do aluno, para acao preventiva do time de cobranca. Recorte oposto ao inadimplente do pacote CR. p_tenant_id NULL = ambos.';

GRANT EXECUTE ON FUNCTION faturamento.get_vencimentos_proximos(integer, uuid)
    TO anon, authenticated, service_role;

-- Wrapper public para supabase.rpc() simples
CREATE OR REPLACE FUNCTION public.get_vencimentos_proximos(
    p_dias      integer DEFAULT 7,
    p_tenant_id uuid    DEFAULT NULL
)
RETURNS TABLE(
    tenant            text,
    tenant_id         uuid,
    aluno             text,
    cpf_cnpj          text,
    telefone          text,
    email             text,
    produto           text,
    numero_parcela    integer,
    data_vencimento   date,
    dias_ate_vencer   integer,
    valor             numeric,
    voomp_contrato_id text
)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT * FROM faturamento.get_vencimentos_proximos(p_dias, p_tenant_id);
$$;

GRANT EXECUTE ON FUNCTION public.get_vencimentos_proximos(integer, uuid)
    TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
