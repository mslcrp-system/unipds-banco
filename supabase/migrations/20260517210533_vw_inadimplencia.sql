-- ============================================================
-- View vw_inadimplencia
--
-- Consolida inadimplencia por parcela com AMBAS as visoes:
--   - Visao Voomp: charges ABERTO com dias_atraso > 1
--   - Visao Unipds: cronograma teorico com dias_atraso_teorico > 1
--
-- Cobertura: somente parcelas de ASSINATURA.
-- Vendas unicas Aguardando ficam de fora (regua de ouro).
--
-- Buckets de aging: EM_DIA (=0), 1_30D, 31_60D, 61_90D, 90PLUS
-- aplicados ao dias_atraso_teorico (visao Unipds, fonte unica).
-- ============================================================

CREATE OR REPLACE VIEW unipds.vw_inadimplencia AS
WITH parcelas_devidas AS (
    -- Pega parcelas teoricas vencidas e nao pagas (todas as visoes)
    SELECT
        vt.contract_id,
        vt.tenant_id,
        vt.student_id,
        vt.product_id,
        vt.voomp_contrato_id,
        vt.numero_parcela,
        vt.data_prevista,
        vt.valor_parcela_previsto,
        vt.status_parcela,
        vt.charge_id,
        vt.voomp_venda_id,
        vt.data_vencimento_real,
        vt.dias_atraso_charge AS dias_atraso_voomp,
        vt.dias_atraso_teorico
    FROM unipds.vw_cronograma_teorico vt
    WHERE vt.status_parcela IN ('EM_ABERTO', 'NAO_EMITIDA')
      AND vt.dias_atraso_teorico > 1   -- regua: atraso > 1 dia
)
SELECT
    pd.contract_id,
    pd.tenant_id,
    pd.student_id,
    pd.product_id,
    pd.voomp_contrato_id,
    s.nome              AS aluno_nome,
    s.cpf_cnpj          AS aluno_cpf,
    s.email             AS aluno_email,
    p.nome              AS produto_nome,
    pd.numero_parcela,
    pd.data_prevista,
    pd.data_vencimento_real,
    pd.valor_parcela_previsto,
    pd.status_parcela,
    pd.dias_atraso_voomp,
    pd.dias_atraso_teorico,
    -- Bucket de aging (Visao Unipds)
    CASE
        WHEN pd.dias_atraso_teorico BETWEEN 2  AND 30  THEN '1_30D'
        WHEN pd.dias_atraso_teorico BETWEEN 31 AND 60  THEN '31_60D'
        WHEN pd.dias_atraso_teorico BETWEEN 61 AND 90  THEN '61_90D'
        WHEN pd.dias_atraso_teorico > 90               THEN '90PLUS'
        ELSE 'EM_DIA'
    END AS bucket_aging,
    -- Flag: cobranca emitida pela Voomp ou nao
    CASE
        WHEN pd.status_parcela = 'EM_ABERTO'   THEN 'VOOMP_EMITIU'
        WHEN pd.status_parcela = 'NAO_EMITIDA' THEN 'VOOMP_NAO_EMITIU'
    END AS situacao_emissao
FROM parcelas_devidas pd
JOIN unipds.students s ON s.student_id = pd.student_id
JOIN unipds.products p ON p.product_id = pd.product_id;

COMMENT ON VIEW unipds.vw_inadimplencia IS
  'Inadimplencia consolidada (assinaturas). Atraso > 1 dia. dias_atraso_teorico = Visao Unipds. dias_atraso_voomp = Visao Voomp. situacao_emissao identifica fragilidade 2.';
