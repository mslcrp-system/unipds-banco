-- ============================================================
-- Adiciona tipo_cobranca e categoria em charges
--
-- tipo_cobranca: 'Assinatura' ou 'Único' (do raw 'Tipo de cobrança')
-- categoria: PAGO, ABERTO, REEMBOLSADO, CHARGEBACK (normalizada)
--
-- Materializar evita CASE WHEN repetido em toda view futura
-- de CR e inadimplencia.
-- ============================================================

ALTER TABLE unipds.charges
  ADD COLUMN IF NOT EXISTS tipo_cobranca text NOT NULL DEFAULT 'Assinatura',
  ADD COLUMN IF NOT EXISTS categoria     text NOT NULL DEFAULT 'PAGO';

-- Defaults sao para a tabela criar sem erro; sera populado pela 2g.
-- Apos popular, podemos remover os defaults se quisermos.

COMMENT ON COLUMN unipds.charges.tipo_cobranca IS 'Assinatura ou Único, vem do raw Tipo de cobrança';
COMMENT ON COLUMN unipds.charges.categoria IS 'PAGO, ABERTO, REEMBOLSADO, CHARGEBACK — normalizada de classificar_raw_line';
