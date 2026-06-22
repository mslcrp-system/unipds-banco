-- ============================================================
-- Seguranca - Batch 1: ligar RLS (deny-all) em tabelas internas/lixo
-- que estavam expostas sem RLS em schema publico-exposto.
--
-- NAO-QUEBRA: nenhuma dessas e lida por front (0 views/0 RPCs as 3
-- primeiras; raw_lines_skipped so pelo ETL via service_role, que tem
-- BYPASSRLS). Ligar RLS sem policy bloqueia anon/authenticated e mantem
-- service_role/owner (ETL, migrations). Reversivel (DISABLE).
--
-- Fora deste batch de proposito:
--   - financeiro.lancamentos_v2  -> pode ter front lendo direto (avaliar)
--   - tmp_dossie_*               -> aqui so travadas; DROP fica p/ depois
--     (sao dossies de analise descartaveis, com PII, 0 consumidores)
-- ============================================================

ALTER TABLE public.tmp_dossie_cartao        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tmp_dossie_boletos       ENABLE ROW LEVEL SECURITY;
ALTER TABLE unipds.raw_lines_skipped        ENABLE ROW LEVEL SECURITY;
ALTER TABLE financeiro.lancamentos_bkp_venc ENABLE ROW LEVEL SECURITY;
