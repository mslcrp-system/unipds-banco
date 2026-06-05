-- ============================================================
-- limpar_imports_antigos v2 — TABLE-SWAP (sem timeout)
--
-- A versao anterior usava DELETE em raw_lines, que com o indice
-- idx_raw_lines_payload_id_venda fica lento e encosta no
-- statement_timeout de 120s ao remover ~10k+ linhas (timeout
-- intermitente observado na ingestao).
--
-- Nova abordagem (table-swap): guarda as linhas a MANTER numa temp,
-- TRUNCATE (instantaneo, sem churn de indice) e reinsere as mantidas.
-- TRUNCATE nao percorre linha a linha nem mexe em indice por tupla,
-- entao roda em milissegundos independente do volume.
--
-- SECURITY DEFINER: TRUNCATE exige privilegio de dono — a funcao
-- roda como owner (postgres), nao como o caller (service_role/anon).
--
-- Mantem: ultima importacao 'concluido' por fonte + qualquer
-- importacao em andamento (status <> 'concluido').
-- raw_lines_skipped eh truncada junto (FK) e repopulada no proximo
-- ETL (as funcoes de skip reinserem a partir das raw_lines atuais).
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
AS $function$
DECLARE
    v_rl_antes  bigint;
    v_rl_depois bigint;
    v_sk_antes  bigint;
    v_imp       bigint;
BEGIN
    -- Conjunto a MANTER: ultima concluida por fonte + em andamento
    CREATE TEMP TABLE _keep ON COMMIT DROP AS
        SELECT DISTINCT ON (fonte_id) import_id
        FROM unipds.raw_imports
        WHERE status = 'concluido'
        ORDER BY fonte_id, imported_at DESC;

    INSERT INTO _keep
        SELECT import_id FROM unipds.raw_imports WHERE status <> 'concluido';

    SELECT COUNT(*) INTO v_rl_antes FROM unipds.raw_lines;
    SELECT COUNT(*) INTO v_sk_antes FROM unipds.raw_lines_skipped;

    -- Guarda as raw_lines a manter
    CREATE TEMP TABLE _keep_lines ON COMMIT DROP AS
        SELECT * FROM unipds.raw_lines
        WHERE import_id IN (SELECT import_id FROM _keep);

    -- Table-swap: trunca as duas (FK) e recoloca so as mantidas
    TRUNCATE unipds.raw_lines, unipds.raw_lines_skipped;
    INSERT INTO unipds.raw_lines SELECT * FROM _keep_lines;

    -- Remove os registros de importacao antigos (poucas linhas, rapido)
    DELETE FROM unipds.raw_imports
    WHERE import_id NOT IN (SELECT import_id FROM _keep);
    GET DIAGNOSTICS v_imp = ROW_COUNT;

    SELECT COUNT(*) INTO v_rl_depois FROM unipds.raw_lines;

    RETURN QUERY SELECT (v_rl_antes - v_rl_depois), v_sk_antes, v_imp;
END;
$function$;

COMMENT ON FUNCTION unipds.limpar_imports_antigos() IS
  'Mantem so a ultima importacao concluida por fonte (+ em andamento). Usa TABLE-SWAP (TRUNCATE + reinsert) em vez de DELETE para evitar timeout do indice. SECURITY DEFINER (TRUNCATE exige owner). raw_lines_skipped eh truncada e repopulada no proximo ETL.';

GRANT EXECUTE ON FUNCTION unipds.limpar_imports_antigos()
    TO anon, authenticated, service_role;
