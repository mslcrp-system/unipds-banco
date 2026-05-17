# DEPRECATED — ingest-voomp-xlsx

Esta Edge Function foi descontinuada em 17/05/2026 por estourar
WORKER_RESOURCE_LIMIT ao processar XLSX da Voomp (~14 MB, 8-9k linhas).

**Substituida por:** `scripts/ingest_voomp.py` (script Python local).

A Edge Function continua deployada mas nao deve ser invocada.
Quando o limite de memoria do Edge Runtime aumentar, considerar
migrar de volta com parser CSV streaming.
