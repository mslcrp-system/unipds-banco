-- ============================================================
-- limpar_imports_antigos v3 — statement_timeout proprio
--
-- Causa raiz do timeout intermitente: a funcao eh chamada pelo
-- script via PostgREST/service_role, cuja conexao herda um
-- statement_timeout curto (~8s do authenticator). O table-swap
-- (TRUNCATE + reinsert de ~17k linhas + rebuild do indice
-- idx_raw_lines_payload_id_venda) ocasionalmente passa de 8s →
-- erro 57014 (canceling statement due to statement timeout).
--
-- Fix: a funcao declara seu PROPRIO statement_timeout (300s) via
-- clausula SET. Aplicado ao entrar na funcao, sobrepoe o limite
-- curto de quem chama — independente de anon/authenticated/
-- service_role. Combinado com o table-swap (rapido), a limpeza
-- nunca mais estoura o timeout.
--
-- Corpo identico a v2 (table-swap); muda so o cabecalho (SET).
-- ============================================================

CREATE OR REPLACE FUNCTION unipds.limpar_imports_antigos()
RETURNS TABLE(
    raw_lines_removidas bigint,
    skipped_removidos   bigint,
    imports_removidos   bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'unipds','public'
SET statement_timeout TO '300s'
AS $function$
DECLARE
    v_rl_antes  bigint;
    v_rl_depois bigint;
    v_sk_antes  bigint;
    v_imp       bigint;
BEGIN
    CREATE TEMP TABLE _keep ON COMMIT DROP AS
        SELECT DISTINCT ON (fonte_id) import_id
        FROM unipds.raw_imports
        WHERE status = 'concluido'
        ORDER BY fonte_id, imported_at DESC;

    INSERT INTO _keep
        SELECT import_id FROM unipds.raw_imports WHERE status <> 'concluido';

    SELECT COUNT(*) INTO v_rl_antes FROM unipds.raw_lines;
    SELECT COUNT(*) INTO v_sk_antes FROM unipds.raw_lines_skipped;

    CREATE TEMP TABLE _keep_lines ON COMMIT DROP AS
        SELECT * FROM unipds.raw_lines
        WHERE import_id IN (SELECT import_id FROM _keep);

    TRUNCATE unipds.raw_lines, unipds.raw_lines_skipped;
    INSERT INTO unipds.raw_lines SELECT * FROM _keep_lines;

    DELETE FROM unipds.raw_imports
    WHERE import_id NOT IN (SELECT import_id FROM _keep);
    GET DIAGNOSTICS v_imp = ROW_COUNT;

    SELECT COUNT(*) INTO v_rl_depois FROM unipds.raw_lines;

    RETURN QUERY SELECT (v_rl_antes - v_rl_depois), v_sk_antes, v_imp;
END;
$function$;

COMMENT ON FUNCTION unipds.limpar_imports_antigos() IS
  'Mantem so a ultima importacao concluida por fonte (+ em andamento) via TABLE-SWAP. SET statement_timeout=300s sobrepoe o limite curto do PostgREST/service_role (causa do timeout 57014). SECURITY DEFINER (TRUNCATE exige owner).';

GRANT EXECUTE ON FUNCTION unipds.limpar_imports_antigos()
    TO anon, authenticated, service_role;
