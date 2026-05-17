-- ============================================================
-- Adaptar charges para suportar vendas unicas
--
-- ETL antigo criava contratos 'fake' (voomp_contrato_id=NULL) para
-- vendas unicas, so para satisfazer FK em charges.contract_id NOT NULL.
-- ETL novo separa: assinaturas tem contract, vendas unicas nao.
--
-- Esta migration:
--   1. Adiciona tenant_id, student_id, product_id em charges (NOT NULL)
--   2. Torna contract_id NULLABLE
--   3. Backfill: preenche os 3 novos campos para os 11.708 charges
--      atuais via JOIN com contracts (verificado: 100% dos charges
--      conseguem ser backfilled).
--   4. Cria indices nas novas FKs para performance de JOIN.
-- ============================================================

-- ETAPA 1: Adicionar colunas (NULL temporariamente para backfill)
ALTER TABLE unipds.charges
    ADD COLUMN tenant_id  uuid,
    ADD COLUMN student_id uuid,
    ADD COLUMN product_id uuid;

-- ETAPA 2: Backfill via contracts
UPDATE unipds.charges c
SET tenant_id  = ct.tenant_id,
    student_id = ct.student_id,
    product_id = ct.product_id
FROM unipds.contracts ct
WHERE c.contract_id = ct.contract_id;

-- ETAPA 3: Verificacao defensiva pre-NOT-NULL
DO $$
DECLARE
    v_nulos bigint;
BEGIN
    SELECT count(*) INTO v_nulos FROM unipds.charges
    WHERE tenant_id IS NULL OR student_id IS NULL OR product_id IS NULL;
    IF v_nulos > 0 THEN
        RAISE EXCEPTION 'Backfill incompleto: % charges com tenant/student/product NULL', v_nulos;
    END IF;
END $$;

-- ETAPA 4: Aplicar NOT NULL + FKs + indices
ALTER TABLE unipds.charges
    ALTER COLUMN tenant_id  SET NOT NULL,
    ALTER COLUMN student_id SET NOT NULL,
    ALTER COLUMN product_id SET NOT NULL,
    ALTER COLUMN contract_id DROP NOT NULL,
    ADD CONSTRAINT charges_tenant_id_fkey  FOREIGN KEY (tenant_id)  REFERENCES unipds.tenants(tenant_id),
    ADD CONSTRAINT charges_student_id_fkey FOREIGN KEY (student_id) REFERENCES unipds.students(student_id),
    ADD CONSTRAINT charges_product_id_fkey FOREIGN KEY (product_id) REFERENCES unipds.products(product_id);

CREATE INDEX idx_charges_tenant_id  ON unipds.charges (tenant_id);
CREATE INDEX idx_charges_student_id ON unipds.charges (student_id);
CREATE INDEX idx_charges_product_id ON unipds.charges (product_id);

COMMENT ON COLUMN unipds.charges.contract_id IS
  'NULL para vendas unicas; preenchido para assinaturas.';
COMMENT ON COLUMN unipds.charges.tenant_id IS
  'Tenant da venda. Obrigatorio (vendas unicas nao tem contrato para inferir).';
COMMENT ON COLUMN unipds.charges.student_id IS
  'Aluno da venda. Obrigatorio.';
COMMENT ON COLUMN unipds.charges.product_id IS
  'Produto vendido. Obrigatorio.';
