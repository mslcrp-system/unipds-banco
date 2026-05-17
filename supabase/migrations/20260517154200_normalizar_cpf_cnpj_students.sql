-- ============================================================
-- Normaliza students.cpf_cnpj removendo mascara
--
-- 6.539 de 6.541 alunos estao com formato 'XXX.XXX.XXX-XX'.
-- ETL novo grava normalizado (so digitos). Sem essa migration,
-- o UPSERT por (tenant_id, cpf_cnpj) inseriria duplicatas em vez
-- de atualizar registros existentes, quebrando a estrategia
-- de preservacao de UUIDs.
--
-- Pre-requisito verificado em produção (17/05): zero conflitos
-- de unicidade apos normalizacao.
--
-- UUIDs e FKs preservados (constraint UNIQUE permanece, apenas
-- valor da coluna muda).
-- ============================================================

UPDATE unipds.students
SET cpf_cnpj = regexp_replace(cpf_cnpj, '[^0-9]', '', 'g'),
    updated_at = now()
WHERE cpf_cnpj ~ '[^0-9]';

-- Verificacao defensiva: nao deve haver duplicatas apos normalizacao
DO $$
DECLARE
    v_dups bigint;
BEGIN
    SELECT count(*) INTO v_dups FROM (
        SELECT tenant_id, cpf_cnpj FROM unipds.students
        GROUP BY 1, 2 HAVING count(*) > 1
    ) x;
    IF v_dups > 0 THEN
        RAISE EXCEPTION 'Normalizacao gerou % duplicatas em students.cpf_cnpj', v_dups;
    END IF;
END $$;
