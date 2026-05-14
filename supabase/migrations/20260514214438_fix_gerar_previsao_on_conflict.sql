CREATE OR REPLACE FUNCTION unipds.gerar_previsao_parcelas(p_contract_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_contract      RECORD;
    v_data_base     DATE;
    v_data_p1       DATE;
    v_valor_p1      NUMERIC(12,2);
    i               INT;
    v_inseridos     INT := 0;
    v_ref           TEXT;
    v_charge_id     UUID;
    v_valor_previsto NUMERIC(12,2);
    v_data_pag      DATE;
    v_status        TEXT;
BEGIN
    -- Busca P1 paga: data e valor real (valor_oferta_linha ou fallback valor_cobrado)
    SELECT
        ch.data_pagamento,
        COALESCE(ch.valor_oferta_linha, ch.faturamento_total, ch.valor_cobrado)
    INTO v_data_p1, v_valor_p1
    FROM unipds.charges ch
    WHERE ch.contract_id    = p_contract_id
      AND ch.numero_parcela = 1
      AND ch.status         = 'Pago'
      AND ch.valor_cobrado  > 0
    LIMIT 1;

    SELECT * INTO v_contract
    FROM unipds.contracts
    WHERE contract_id = p_contract_id;

    v_data_base := COALESCE(v_data_p1, v_contract.data_primeira_venda);
    v_valor_p1  := COALESCE(v_valor_p1, v_contract.valor_oferta);

    -- Garante que nunca seja NULL
    IF v_valor_p1 IS NULL OR v_valor_p1 = 0 THEN
        v_valor_p1 := v_contract.valor_oferta;
    END IF;

    FOR i IN 1..COALESCE(v_contract.recorrencia_total, 12) LOOP
        v_ref := 'PRV-' || v_contract.contract_ref || '-P' || LPAD(i::TEXT, 2, '0');

        SELECT ch.charge_id, ch.data_pagamento,
               COALESCE(ch.valor_oferta_linha, ch.faturamento_total, ch.valor_cobrado)
        INTO v_charge_id, v_data_pag, v_valor_previsto
        FROM unipds.charges ch
        WHERE ch.contract_id    = p_contract_id
          AND ch.numero_parcela = i
          AND ch.status         = 'Pago'
          AND ch.valor_cobrado  > 0
        LIMIT 1;

        IF v_charge_id IS NULL THEN
            v_valor_previsto := v_valor_p1;
            v_data_pag       := NULL;
            v_status := CASE
                WHEN (v_data_base + ((i - 1) || ' months')::INTERVAL) < CURRENT_DATE
                THEN 'vencido'
                ELSE 'previsto'
            END;
        ELSE
            v_status := 'pago';
            -- Garante valor não nulo mesmo nas pagas
            IF v_valor_previsto IS NULL OR v_valor_previsto = 0 THEN
                v_valor_previsto := v_valor_p1;
            END IF;
        END IF;

        INSERT INTO unipds.previsao_parcelas (
            contract_id, tenant_id, numero_parcela, total_parcelas,
            previsao_ref, valor_previsto, data_prevista, data_pagamento,
            charge_id, status
        ) VALUES (
            p_contract_id,
            v_contract.tenant_id,
            i,
            COALESCE(v_contract.recorrencia_total, 12),
            v_ref,
            v_valor_previsto,
            v_data_base + ((i - 1) || ' months')::INTERVAL,
            v_data_pag,
            v_charge_id,
            v_status
        )
        ON CONFLICT (previsao_ref) DO UPDATE
            SET status         = EXCLUDED.status,
                data_pagamento = EXCLUDED.data_pagamento,
                charge_id      = EXCLUDED.charge_id;

        v_inseridos := v_inseridos + 1;
    END LOOP;

    RETURN v_inseridos;
END;
$function$
;
