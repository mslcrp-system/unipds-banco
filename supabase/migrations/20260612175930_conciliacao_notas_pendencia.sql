-- ============================================================
-- Conciliacao — Item F: notas de justificativa nas pendencias.
-- (Solicitacao da sessao front 2026-06-12.)
--
-- Registra o motivo de cada pendencia que fica em aberto no
-- fechamento. 1 nota por pendencia (lado Pipe OU lado Voomp),
-- editavel enquanto o mes esta ABERTO, travada quando FECHADO.
--
-- Itens A-E do adendo ja estavam aplicados (v3 + v3.1). Esta
-- migration cobre apenas o Item F, que era o unico pendente.
--
-- Ajuste do mentor sobre a spec: +trigger set_updated_at. A spec
-- declara updated_at mas, sem trigger, a coluna nunca mudaria num
-- UPDATE (so teria o default do INSERT) — bug silencioso.
-- ============================================================

CREATE TABLE conciliacao.notas_pendencia (
  nota_id      uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid        NOT NULL REFERENCES unipds.tenants(tenant_id),
  ano_mes      text        NOT NULL CHECK (ano_mes ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  pipe_deal_id bigint,                -- pendencia do lado Pipe (deal_id estavel)
  snapshot_id  uuid        REFERENCES conciliacao.voomp_snapshot(snapshot_id) ON DELETE CASCADE,
  motivo       text        NOT NULL CHECK (motivo IN
                 ('PAGAMENTO_NEGADO','PAGO_OUTRO_MES','CANCELADO','OUTRO')),
  nota         text,                  -- texto livre complementar
  created_by   uuid,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  CHECK (pipe_deal_id IS NOT NULL OR snapshot_id IS NOT NULL)
);

-- 1 nota por pendencia (parciais: um lado por vez)
CREATE UNIQUE INDEX notas_pendencia_deal_uq
  ON conciliacao.notas_pendencia (tenant_id, ano_mes, pipe_deal_id)
  WHERE pipe_deal_id IS NOT NULL;
CREATE UNIQUE INDEX notas_pendencia_snap_uq
  ON conciliacao.notas_pendencia (snapshot_id)
  WHERE snapshot_id IS NOT NULL;
CREATE INDEX notas_pendencia_tenant_mes_idx
  ON conciliacao.notas_pendencia (tenant_id, ano_mes);

GRANT SELECT, INSERT, UPDATE, DELETE ON conciliacao.notas_pendencia TO authenticated;
GRANT SELECT ON conciliacao.notas_pendencia TO anon;
GRANT ALL ON conciliacao.notas_pendencia TO service_role;
ALTER TABLE conciliacao.notas_pendencia ENABLE ROW LEVEL SECURITY;
CREATE POLICY "authenticated full access" ON conciliacao.notas_pendencia
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

COMMENT ON TABLE conciliacao.notas_pendencia IS
  'Justificativa de pendencias em aberto no fechamento. 1 nota por pendencia (pipe_deal_id OU snapshot_id). Lado Voomp cascateia se a fotografia for regenerada; lado Pipe sobrevive ao full-replace. Travada por mes fechado.';

-- ─── Trava de mes fechado (mesma das demais tabelas) ──────────
CREATE TRIGGER bloquear_mes_fechado
  BEFORE INSERT OR UPDATE OR DELETE ON conciliacao.notas_pendencia
  FOR EACH ROW EXECUTE FUNCTION conciliacao.tg_bloquear_mes_fechado();

-- ─── Manutencao de updated_at (melhoria do mentor) ────────────
CREATE OR REPLACE FUNCTION conciliacao.tg_set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON conciliacao.notas_pendencia
  FOR EACH ROW EXECUTE FUNCTION conciliacao.tg_set_updated_at();

NOTIFY pgrst, 'reload schema';
