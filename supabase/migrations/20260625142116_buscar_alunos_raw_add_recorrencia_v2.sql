-- ============================================================
-- buscar_alunos_raw: + recorrencia_atual / recorrencia_total
--
-- Migration aplicada por outra sessao direto no banco (20260625142116);
-- trazida pro repo retroativamente (governanca: toda migration vive aqui).
-- Adiciona as colunas de recorrencia ao retorno da funcao usada pelo
-- extrato Voomp p/ buscar dados de aluno por ID de venda.
-- ============================================================

DROP FUNCTION IF EXISTS unipds.buscar_alunos_raw(uuid, text[]);

CREATE FUNCTION unipds.buscar_alunos_raw(p_fonte_id uuid, p_ids_venda text[])
 RETURNS TABLE(id_venda text, nome text, cpf_cnpj text, email text, telefone text, endereco_fisico text, uf_origem text, produto text, recorrencia_atual text, recorrencia_total text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT DISTINCT ON (rl.payload->>'ID Venda')
    rl.payload->>'ID Venda'           AS id_venda,
    rl.payload->>'Nome do comprador'  AS nome,
    regexp_replace(coalesce(rl.payload->>'CPF/CNPJ',''), '\D', '', 'g') AS cpf_cnpj,
    rl.payload->>'Email do comprador' AS email,
    rl.payload->>'Número de telefone' AS telefone,
    rl.payload->>'Endereço físico'    AS endereco_fisico,
    rl.payload->>'UF Origem'          AS uf_origem,
    rl.payload->>'Nome do produto'    AS produto,
    rl.payload->>'Recorrência atual'  AS recorrencia_atual,
    rl.payload->>'Recorrência total'  AS recorrencia_total
  FROM unipds.raw_lines rl
  JOIN unipds.raw_imports ri ON ri.import_id = rl.import_id
  WHERE ri.fonte_id = p_fonte_id
    AND rl.payload->>'ID Venda' = ANY(p_ids_venda)
    AND rl.payload->>'Nome do comprador' IS NOT NULL
$function$;
