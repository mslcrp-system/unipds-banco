CREATE OR REPLACE VIEW unipds.v_inadimplencia AS
SELECT s.student_id,
    s.nome,
    s.cpf_cnpj,
    s.email,
    s.telefone,
    c.contract_ref,
    c.tipo_cobranca,
    c.status_contrato,
    p.classe AS tipo_curso,
    pp.previsao_id,
    pp.previsao_ref,
    pp.numero_parcela,
    pp.total_parcelas,
    pp.valor_previsto AS valor_devido,
    pp.data_prevista AS data_vencimento,
    CURRENT_DATE - pp.data_prevista AS dias_atraso,
        CASE
            WHEN (CURRENT_DATE - pp.data_prevista) >= 1 AND (CURRENT_DATE - pp.data_prevista) <= 30 THEN '1-30 dias'::text
            WHEN (CURRENT_DATE - pp.data_prevista) >= 31 AND (CURRENT_DATE - pp.data_prevista) <= 60 THEN '31-60 dias'::text
            WHEN (CURRENT_DATE - pp.data_prevista) >= 61 AND (CURRENT_DATE - pp.data_prevista) <= 90 THEN '61-90 dias'::text
            WHEN (CURRENT_DATE - pp.data_prevista) > 90 THEN '+90 dias'::text
            ELSE NULL::text
        END AS faixa_atraso,
    pp.tenant_id,
        CASE pp.tenant_id
            WHEN '70b668e4-be85-459b-8dbb-3876929ac850'::uuid THEN 'Java'::text
            WHEN 'e717e24d-fb30-4ed0-83d3-bb8ea0b66783'::uuid THEN 'IA'::text
            ELSE NULL::text
        END AS tenant_nome,
    COUNT(*) OVER (PARTITION BY pp.contract_id) >= 3 AS sugere_extrajudicial
   FROM unipds.previsao_parcelas pp
     JOIN unipds.contracts c ON c.contract_id = pp.contract_id
     JOIN unipds.students s ON s.student_id = c.student_id
     JOIN unipds.v_produtos_classificados p ON p.product_id = c.product_id
  WHERE pp.status = 'vencido'::text AND c.contrato_canonico = true AND c.status_contrato <> 'Cancelado'::text AND p.classe <> 'ADMINISTRATIVO'::text AND (EXISTS ( SELECT 1
           FROM unipds.charges ch
          WHERE ch.contract_id = c.contract_id AND ch.status = 'Pago'::text AND COALESCE(ch.numero_parcela, 1) = 1))
  ORDER BY (CURRENT_DATE - pp.data_prevista) DESC;
