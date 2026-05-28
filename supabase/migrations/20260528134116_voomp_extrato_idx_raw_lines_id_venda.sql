CREATE INDEX IF NOT EXISTS idx_raw_lines_payload_id_venda
ON unipds.raw_lines ((payload->>'ID Venda'));
ANALYZE unipds.raw_lines;
