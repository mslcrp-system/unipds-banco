-- ============================================================
-- Funcao orquestradora processar_raw_lines
--
-- Chama as 6 sub-funcoes na ordem correta de dependencia:
--   1. products (sem deps)
--   2. students (so alunos qualificados pela regua de ouro)
--   3. contracts (depende de students + products)
--   4. charges (depende de students + products + contracts via JOIN)
--   5. payment_attempts (depende de students + products + contracts)
--   6. refunds (depende de charges)
--
-- Modos:
--   'full'  - processa todas as raw_lines (default)
--   'delta' - processa so raw_lines de imports recentes (TODO futuro)
--
-- Retorna stats consolidadas de cada etapa.
-- ============================================================

CREATE OR REPLACE FUNCTION unipds.processar_raw_lines(p_modo text DEFAULT 'full')
RETURNS TABLE(
    etapa text,
    inseridos bigint,
    atualizados bigint,
    skipped bigint
)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_prod   record;
    v_stud   record;
    v_cont   record;
    v_charg  record;
    v_pay    record;
    v_ref    record;
BEGIN
    -- 1. Products
    SELECT * INTO v_prod FROM unipds.upsert_products_from_raw(p_modo);
    etapa := 'products';
    inseridos := v_prod.inseridos;
    atualizados := v_prod.atualizados;
    skipped := v_prod.skipped;
    RETURN NEXT;

    -- 2. Students (apenas alunos qualificados)
    SELECT * INTO v_stud FROM unipds.upsert_students_from_raw(p_modo);
    etapa := 'students';
    inseridos := v_stud.inseridos;
    atualizados := v_stud.atualizados;
    skipped := v_stud.skipped_cpf + v_stud.skipped_lead;
    RETURN NEXT;

    -- 3. Contracts (so assinaturas)
    SELECT * INTO v_cont FROM unipds.upsert_contracts_from_raw(p_modo);
    etapa := 'contracts';
    inseridos := v_cont.inseridos;
    atualizados := v_cont.atualizados;
    skipped := v_cont.skipped;
    RETURN NEXT;

    -- 4. Charges
    SELECT * INTO v_charg FROM unipds.insert_charges_from_raw(p_modo);
    etapa := 'charges';
    inseridos := v_charg.inseridos;
    atualizados := v_charg.atualizados;
    skipped := 0;
    RETURN NEXT;

    -- 5. Payment_attempts
    SELECT * INTO v_pay FROM unipds.insert_payment_attempts_from_raw(p_modo);
    etapa := 'payment_attempts';
    inseridos := v_pay.inseridos;
    atualizados := v_pay.atualizados;
    skipped := 0;
    RETURN NEXT;

    -- 6. Refunds (depende de charges existentes)
    SELECT * INTO v_ref FROM unipds.insert_refunds_from_raw(p_modo);
    etapa := 'refunds';
    inseridos := v_ref.inseridos;
    atualizados := v_ref.atualizados;
    skipped := 0;
    RETURN NEXT;
END;
$function$;

COMMENT ON FUNCTION unipds.processar_raw_lines(text) IS
  'Orquestradora do ETL Voomp. Chama as 6 sub-funcoes em ordem de dependencia. Retorna stats por etapa.';
