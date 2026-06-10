CREATE OR REPLACE FUNCTION unipds.buscar_contratos_raw(p_fonte_id uuid, p_ids_venda text[])
RETURNS TABLE (id_venda text, id_contrato text, cpf text, email text, produto text, periodo text, recorrencia_total text)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT DISTINCT ON (rl.payload->>'ID Venda')
    rl.payload->>'ID Venda'                   AS id_venda,
    rl.payload->>'ID Contrato'                AS id_contrato,
    regexp_replace(coalesce(rl.payload->>'CPF/CNPJ',''),'\D','','g') AS cpf,
    rl.payload->>'Email do comprador'         AS email,
    rl.payload->>'Nome do produto'            AS produto,
    rl.payload->>'Período'                    AS periodo,
    rl.payload->>'Recorrência total'          AS recorrencia_total
  FROM unipds.raw_lines rl
  JOIN unipds.raw_imports ri ON ri.import_id = rl.import_id
  WHERE ri.fonte_id = p_fonte_id
    AND rl.payload->>'ID Venda' = ANY(p_ids_venda)
$$;
GRANT EXECUTE ON FUNCTION unipds.buscar_contratos_raw(uuid, text[]) TO anon, authenticated, service_role;
