-- ============================================================
-- Funcao unipds.limpar_imports_antigos()
--
-- Cada arquivo Voomp ingerido eh um SNAPSHOT HISTORICO COMPLETO
-- (todas as movimentacoes desde o inicio). Logo, a importacao mais
-- recente de cada fonte ja contem tudo — as anteriores sao 100%
-- redundantes e so incham raw_lines (que chegou a 510 MB / 217k linhas,
-- causando timeout no upsert_students).
--
-- Esta funcao mantem APENAS a ultima importacao 'concluido' de cada
-- fonte (+ qualquer importacao em andamento) e remove o resto, na
-- ordem correta de FK:
--   1. raw_lines_skipped (FK SET NULL, mas limpamos por import_id)
--   2. raw_lines        (FK NO ACTION para raw_imports)
--   3. raw_imports
--
-- Idempotente: rodar varias vezes seguidas nao causa efeito extra.
-- Seguro para o ETL: como as funcoes sao UPSERT por chave natural,
-- reprocessar so a ultima importacao reproduz exatamente o mesmo
-- estado das tabelas finais (students/contracts/charges/etc).
--
-- Deve ser chamada ao final de cada ingestao (ou manualmente).
-- ============================================================

CREATE OR REPLACE FUNCTION unipds.limpar_imports_antigos()
RETURNS TABLE(
    raw_lines_removidas   bigint,
    skipped_removidos     bigint,
    imports_removidos     bigint
)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_rl  bigint := 0;
    v_sk  bigint := 0;
    v_imp bigint := 0;
BEGIN
    -- Conjunto a MANTER: ultima importacao concluida por fonte +
    -- qualquer importacao ainda em andamento (status <> 'concluido')
    CREATE TEMP TABLE _keep ON COMMIT DROP AS
        SELECT DISTINCT ON (fonte_id) import_id
        FROM unipds.raw_imports
        WHERE status = 'concluido'
        ORDER BY fonte_id, imported_at DESC;

    INSERT INTO _keep
        SELECT import_id
        FROM unipds.raw_imports
        WHERE status <> 'concluido';

    -- 1) Inbox de skips das importacoes antigas (inclui orfas com import_id NULL)
    DELETE FROM unipds.raw_lines_skipped
    WHERE import_id IS NULL
       OR import_id NOT IN (SELECT import_id FROM _keep);
    GET DIAGNOSTICS v_sk = ROW_COUNT;

    -- 2) Linhas raw das importacoes antigas
    DELETE FROM unipds.raw_lines
    WHERE import_id NOT IN (SELECT import_id FROM _keep);
    GET DIAGNOSTICS v_rl = ROW_COUNT;

    -- 3) Registros de importacao antigos
    DELETE FROM unipds.raw_imports
    WHERE import_id NOT IN (SELECT import_id FROM _keep);
    GET DIAGNOSTICS v_imp = ROW_COUNT;

    RETURN QUERY SELECT v_rl, v_sk, v_imp;
END;
$function$;

COMMENT ON FUNCTION unipds.limpar_imports_antigos() IS
  'Mantem apenas a ultima importacao concluida por fonte (+ em andamento) e remove raw_lines/raw_lines_skipped/raw_imports antigos. Seguro: ETL eh UPSERT, reprocessar a ultima importacao reproduz o mesmo estado. Chamar ao fim de cada ingestao.';

GRANT EXECUTE ON FUNCTION unipds.limpar_imports_antigos()
    TO anon, authenticated, service_role;
