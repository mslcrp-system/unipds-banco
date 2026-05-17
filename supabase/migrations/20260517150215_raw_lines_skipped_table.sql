-- ============================================================
-- Tabela raw_lines_skipped
--
-- Armazena linhas do raw que o ETL nao conseguiu processar
-- (categoria DESCONHECIDO retornada por classificar_raw_line).
--
-- Funciona como fila de inbox: skip aparece, monitor manda
-- Discord, voce decide tratamento, atualiza classificar_raw_line,
-- reprocessa via processar_raw_lines('full'), o skip eh absorvido
-- (linha some daqui automaticamente pois nao cai mais em DESCONHECIDO).
-- ============================================================

CREATE TABLE unipds.raw_lines_skipped (
    skip_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    line_id          uuid REFERENCES unipds.raw_lines(line_id) ON DELETE SET NULL,
    import_id        uuid REFERENCES unipds.raw_imports(import_id) ON DELETE SET NULL,
    payload          jsonb NOT NULL,
    motivo_skip      text NOT NULL,
    status_raw       text,
    processed_at     timestamptz NOT NULL DEFAULT now(),
    notified_at      timestamptz,
    resolved_at      timestamptz,
    resolution_note  text
);

CREATE INDEX idx_raw_lines_skipped_notified
    ON unipds.raw_lines_skipped (notified_at)
    WHERE notified_at IS NULL;

CREATE INDEX idx_raw_lines_skipped_status_raw
    ON unipds.raw_lines_skipped (status_raw);

COMMENT ON TABLE unipds.raw_lines_skipped IS
  'Linhas do raw que classificar_raw_line retornou DESCONHECIDO. Funciona como inbox: monitor agendado consulta WHERE notified_at IS NULL e envia Discord agrupado por status_raw.';

COMMENT ON COLUMN unipds.raw_lines_skipped.payload IS
  'Copia do payload da raw_line original (preserva mesmo se raw_lines for limpo).';

COMMENT ON COLUMN unipds.raw_lines_skipped.notified_at IS
  'Quando a Edge Function unipds-etl-monitor enviou notificacao Discord. NULL = nao notificado ainda.';

COMMENT ON COLUMN unipds.raw_lines_skipped.resolved_at IS
  'Quando o caso foi absorvido (classificar_raw_line atualizada e reprocessamento feito).';
