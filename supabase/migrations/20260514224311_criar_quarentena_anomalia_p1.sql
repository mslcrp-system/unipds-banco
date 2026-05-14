-- ============================================================
-- PARTE 1: Tabela de quarentena para casos com anomalia
-- ============================================================

CREATE TABLE cobranca.casos_anomalia (
    caso_id          uuid        NOT NULL,
    tenant_id        uuid        NOT NULL,
    contract_id      uuid        NOT NULL,
    valor_total_aberto numeric(12,2) NOT NULL,
    parcelas_vencidas  integer   NOT NULL,
    faixa_aging      cobranca.faixa_aging NOT NULL,
    data_abertura    timestamptz NOT NULL,
    tipo_anomalia    text        NOT NULL,
    detectado_em     timestamptz NOT NULL DEFAULT now(),
    observacao       text,

    CONSTRAINT casos_anomalia_pkey PRIMARY KEY (caso_id),
    CONSTRAINT casos_anomalia_contract_id_fkey
        FOREIGN KEY (contract_id) REFERENCES unipds.contracts(contract_id)
);

CREATE INDEX idx_casos_anomalia_contract_id ON cobranca.casos_anomalia (contract_id);

COMMENT ON TABLE cobranca.casos_anomalia IS
    'Registros que entraram em cobranca.cobranca_casos mas não atendem à definição oficial de inadimplência (ex: contratos de assinatura sem P1 paga). Segregados para investigação do Suporte; não fazem parte da carteira de cobrança ativa.';

-- ============================================================
-- PARTE 2: Mover os 5 órfãos sem P1 paga para a quarentena
-- ============================================================

INSERT INTO cobranca.casos_anomalia (
    caso_id,
    tenant_id,
    contract_id,
    valor_total_aberto,
    parcelas_vencidas,
    faixa_aging,
    data_abertura,
    tipo_anomalia,
    observacao
)
SELECT
    caso_id,
    tenant_id,
    contract_id,
    valor_total_aberto,
    parcelas_vencidas,
    faixa_aging,
    data_abertura,
    'sem_p1',
    'Contrato de assinatura sem P1 paga - nao atende definicao oficial de inadimplencia. Carga original de 04/05.'
FROM cobranca.cobranca_casos
WHERE contract_id IN (
    '11e37b01-806e-49af-9e11-45e2f9e5a6a2',
    '17c4ffc8-b748-4717-a568-6802cdb8059e',
    '30678001-9c8f-4113-b3ca-a3c8a9f3ed2f',
    '0dcfba3a-6194-47e4-81fb-0ef0a8a80a94',
    '1cf701ac-82f7-40c9-bc11-db64dbd2df6e'
);

DELETE FROM cobranca.cobranca_casos
WHERE contract_id IN (
    '11e37b01-806e-49af-9e11-45e2f9e5a6a2',
    '17c4ffc8-b748-4717-a568-6802cdb8059e',
    '30678001-9c8f-4113-b3ca-a3c8a9f3ed2f',
    '0dcfba3a-6194-47e4-81fb-0ef0a8a80a94',
    '1cf701ac-82f7-40c9-bc11-db64dbd2df6e'
);
