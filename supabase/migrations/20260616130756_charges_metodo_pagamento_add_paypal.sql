-- ============================================================
-- charges.metodo_pagamento: incluir 'Paypal'.
--
-- A Voomp passou a aceitar PayPal. Surgiu 1 cobranca (venda
-- 1653112, Java, Gabriel Siodoni) com metodo 'Paypal', que a
-- charges_metodo_pagamento_check (so Cartao/Boleto/Pix) rejeitava,
-- quebrando o ETL insert_charges_from_raw na ingestao de 16/06.
--
-- Confirmado no raw atual que 'Paypal' eh o unico valor novo.
-- ============================================================

ALTER TABLE unipds.charges
  DROP CONSTRAINT charges_metodo_pagamento_check;
ALTER TABLE unipds.charges
  ADD CONSTRAINT charges_metodo_pagamento_check
  CHECK (metodo_pagamento = ANY (ARRAY['Cartão de Crédito'::text, 'Boleto'::text, 'Pix'::text, 'Paypal'::text]));
