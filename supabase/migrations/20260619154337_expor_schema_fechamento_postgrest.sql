-- ============================================================
-- Expor o schema `fechamento` no PostgREST.
--
-- Adiciona 'fechamento' a lista pgrst.db_schemas do role authenticator
-- (override controlado por SQL, nao pelo dashboard). Sem isso, o repo de
-- fechamento nao alcanca as views via REST/supabase-js, mesmo com GRANT.
--
-- Lista anterior preservada + fechamento no fim.
-- ============================================================

ALTER ROLE authenticator SET pgrst.db_schemas =
  'public, graphql_public, storage, unipds, cobranca, faturamento, financeiro, conciliacao, fechamento';

NOTIFY pgrst, 'reload config';
NOTIFY pgrst, 'reload schema';
