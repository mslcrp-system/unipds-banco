# _auditoria

Esta pasta preserva artefatos gerados durante a fase de bootstrapping do repositório, para referência histórica.

## 20260514000000_baseline_manual.sql.bak

Baseline extraído manualmente em 14/05/2026 via consultas diretas ao `pg_catalog` da produção (projeto `rgdjacvmwnsbrczxjngn`), antes do Docker estar disponível para executar `supabase db pull`.

**NÃO deve ser aplicado.** O schema oficial e completo está em:

```
supabase/migrations/20260514201239_remote_schema.sql
```

O arquivo oficial foi gerado por `supabase db pull` e complementado com as 15 views extraídas via `pg_get_viewdef`. É o único baseline que deve ser aplicado.
