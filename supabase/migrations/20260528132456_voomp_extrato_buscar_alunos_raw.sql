CREATE OR REPLACE FUNCTION unipds.buscar_alunos_raw(p_fonte_id uuid, p_ids_venda text[])
RETURNS TABLE (
  id_venda text,
  nome text,
  cpf_cnpj text,
  email text,
  telefone text,
  endereco_fisico text,
  uf_origem text,
  produto text
)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT DISTINCT ON (rl.payload->>'ID Venda')
    rl.payload->>'ID Venda'           AS id_venda,
    rl.payload->>'Nome do comprador'  AS nome,
    regexp_replace(coalesce(rl.payload->>'CPF/CNPJ',''), '\D', '', 'g') AS cpf_cnpj,
    rl.payload->>'Email do comprador' AS email,
    rl.payload->>'Número de telefone' AS telefone,
    rl.payload->>'Endereço físico'    AS endereco_fisico,
    rl.payload->>'UF Origem'          AS uf_origem,
    rl.payload->>'Nome do produto'    AS produto
  FROM unipds.raw_lines rl
  JOIN unipds.raw_imports ri ON ri.import_id = rl.import_id
  WHERE ri.fonte_id = p_fonte_id
    AND rl.payload->>'ID Venda' = ANY(p_ids_venda)
    AND rl.payload->>'Nome do comprador' IS NOT NULL
$$;

GRANT EXECUTE ON FUNCTION unipds.buscar_alunos_raw(uuid, text[]) TO anon, authenticated, service_role;
