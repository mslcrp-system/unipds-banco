-- ============================================================
-- PARTE 1: Remover jobs anteriores (idempotência)
-- ============================================================

SELECT cron.unschedule(jobname)
FROM cron.job
WHERE jobname IN (
    'unipds_recalcular_vencida_1',
    'unipds_gerar_previsoes',
    'unipds_recalcular_vencida_2',
    'unipds_gerar_casos'
);

-- ============================================================
-- PARTE 2: Criar os 4 jobs diários às 09:00 (UTC)
-- ============================================================

SELECT cron.schedule('unipds_recalcular_vencida_1', '0 9 * * *',
    'SELECT unipds.recalcular_previsao_vencida();');

SELECT cron.schedule('unipds_gerar_previsoes', '5 9 * * *',
    'SELECT unipds.gerar_previsoes_pendentes();');

SELECT cron.schedule('unipds_recalcular_vencida_2', '10 9 * * *',
    'SELECT unipds.recalcular_previsao_vencida();');

SELECT cron.schedule('unipds_gerar_casos', '15 9 * * *',
    'SELECT cobranca.gerar_casos_inadimplencia();');
