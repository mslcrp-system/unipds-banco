-- ============================================================
-- Adaptar payment_attempts para ETL novo (paridade com charges)
--
-- Mudancas:
--   - contract_id: NOT NULL -> NULLABLE (vendas unicas)
--   - Adicionar FKs: tenant_id, student_id, product_id
--   - Adicionar campos: tipo_cobranca, categoria, status,
--                       numero_parcela, taxa_voomp
--   - Renomear: valor -> valor_cobrado
--   - Renomear: tentativa_em -> data_tentativa
--
-- Tabela esta vazia (pos-reset): NOT NULL imediato apos ADD COLUMN.
-- ============================================================

-- Tornar contract_id nullable
ALTER TABLE unipds.payment_attempts
  ALTER COLUMN contract_id DROP NOT NULL;

-- Renomear para paridade com charges
ALTER TABLE unipds.payment_attempts
  RENAME COLUMN valor TO valor_cobrado;
ALTER TABLE unipds.payment_attempts
  RENAME COLUMN tentativa_em TO data_tentativa;

-- Adicionar colunas (com FKs onde aplicavel)
ALTER TABLE unipds.payment_attempts
  ADD COLUMN IF NOT EXISTS tenant_id     uuid REFERENCES unipds.tenants(tenant_id),
  ADD COLUMN IF NOT EXISTS student_id    uuid REFERENCES unipds.students(student_id),
  ADD COLUMN IF NOT EXISTS product_id    uuid REFERENCES unipds.products(product_id),
  ADD COLUMN IF NOT EXISTS tipo_cobranca text,
  ADD COLUMN IF NOT EXISTS categoria     text,
  ADD COLUMN IF NOT EXISTS status        text,
  ADD COLUMN IF NOT EXISTS numero_parcela integer,
  ADD COLUMN IF NOT EXISTS taxa_voomp    numeric;

-- Tabela vazia pos-reset: aplicar NOT NULL nas colunas obrigatorias
ALTER TABLE unipds.payment_attempts
  ALTER COLUMN tenant_id     SET NOT NULL,
  ALTER COLUMN student_id    SET NOT NULL,
  ALTER COLUMN product_id    SET NOT NULL,
  ALTER COLUMN tipo_cobranca SET NOT NULL,
  ALTER COLUMN categoria     SET NOT NULL,
  ALTER COLUMN status        SET NOT NULL;

-- Alterar data_tentativa para date (raw vem como string, mas casts ja resolvem)
-- Nao precisa alterar tipo: timestamptz aceita date implicitamente

COMMENT ON COLUMN unipds.payment_attempts.tenant_id      IS 'FK para tenants';
COMMENT ON COLUMN unipds.payment_attempts.student_id     IS 'FK para students - apenas alunos';
COMMENT ON COLUMN unipds.payment_attempts.product_id     IS 'FK para products';
COMMENT ON COLUMN unipds.payment_attempts.contract_id    IS 'NULL para vendas unicas; preenchido para assinaturas';
COMMENT ON COLUMN unipds.payment_attempts.tipo_cobranca  IS 'Assinatura ou Único';
COMMENT ON COLUMN unipds.payment_attempts.categoria      IS 'Sempre TENTATIVA_RECUSADA (paridade com charges)';
COMMENT ON COLUMN unipds.payment_attempts.status         IS 'Status original Voomp (Recusado, failed, etc)';
COMMENT ON COLUMN unipds.payment_attempts.valor_cobrado  IS 'Valor que a Voomp tentou cobrar (Valor Oferta)';
COMMENT ON COLUMN unipds.payment_attempts.data_tentativa IS 'Data da tentativa de cobranca';
