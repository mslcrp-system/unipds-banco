-- ============================================================
-- Limpeza de funcoes orfas pos-reset
--
-- unipds.get_parcelas_vencidas tem assinatura (uuid), nao () — o DROP
-- anterior fez skip silencioso.
--
-- As 3 funcoes do schema cobranca eram triggers das tabelas dropadas;
-- ficaram dormentes sem mesa para acionar.
-- ============================================================

DROP FUNCTION IF EXISTS unipds.get_parcelas_vencidas(uuid) CASCADE;
DROP FUNCTION IF EXISTS cobranca.atualizar_ultima_interacao() CASCADE;
DROP FUNCTION IF EXISTS cobranca.registrar_encerramento() CASCADE;
DROP FUNCTION IF EXISTS cobranca.set_updated_at() CASCADE;
