# Integração — Dashboard de Fechamento × Banco (Supabase)

Guia pra plugar o **repo do dashboard de fechamento** nas views de faturamento
gerencial expostas pelo banco. **Tudo é read-only** — o banco calcula, o front lê
e faz a própria fotografia.

> Projeto Supabase: `rgdjacvmwnsbrczxjngn` · Schema: **`fechamento`**

---

## 1. Modelo (entenda antes de plugar)

Faturamento gerencial é **bookings/TCV**, não caixa:

- **Competência = data de pagamento.**
- **Assinatura:** ao pagar a 1ª parcela, reconhece o **contrato inteiro** (TCV) no mês da P1.
- **À vista:** valor cheio no mês do pagamento.
- **Reembolso** e **churn** entram como **reversões** (linhas negativas), no mês do evento.
  A lógica é autocorretiva: reconhecido acumulado = realizado.

Cadeia do demonstrativo:

```
Faturamento reconhecido
  (−) Taxa Voomp          ┐ splits de pagamento que NÃO chegam na Unipds
  (−) Taxa Secretaria     ┘ (co-produtor) → não são tributados
  = Valor Líquido
  (−) ISS 5% · PIS 0,65% · COFINS 3% · IRPJ 8% · CSLL 2,88%   (% sobre o líquido)
  = Lucratividade
```

---

## 2. Conexão

Mesmo projeto Supabase. No `.env` do repo de fechamento:

```env
NEXT_PUBLIC_SUPABASE_URL=https://rgdjacvmwnsbrczxjngn.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon key>
# server-side (se for ler via backend): SUPABASE_SERVICE_ROLE_KEY=<service role>
```

---

## 3. Apontar para o schema `fechamento`

As views **não** estão no schema `public`. Duas formas:

**supabase-js** — fixar o schema no client ou por query:

```ts
import { createClient } from '@supabase/supabase-js'

// opção A: client dedicado ao schema
const fechamento = createClient(url, anonKey, { db: { schema: 'fechamento' } })

// opção B: por query, reusando um client existente
const { data } = await supabase.schema('fechamento')
  .from('vw_lucratividade_mensal')
  .select('*')
```

**REST cru** — header de schema:

```
GET /rest/v1/vw_lucratividade_mensal?ano_mes=eq.2026-05
Accept-Profile: fechamento
apikey: <key>
Authorization: Bearer <key>
```

---

## 4. Views disponíveis

| View | Grão | Uso |
|---|---|---|
| `vw_lucratividade_mensal` | tenant × mês × **classe** × **categoria** | **demonstrativo** — receita → líquido → impostos → lucro |
| `vw_faturamento_mensal` | tenant × mês × **classe** × **categoria** | faturamento (bruto / reembolso / churn / líquido) |
| `vw_faturamento_eventos` | 1 linha por evento | drill-down (booking/reversão por contrato/venda) |
| `vw_recebimentos_mensal` | tenant × mês × tipo × categoria | **caixa** — recebido do mês (Nova × Recorrente) |
| `parametros_fiscais` | — | alíquotas vigentes (exibir/simular no front) |

> **Faturamento gerencial** (bookings/TCV, reconhece o contrato cheio na entrada) ≠ **Recebimentos** (`vw_recebimentos_mensal`, só o que foi efetivamente recebido no mês). Ambos na régua `faturamento_total` — o total recebido bate com o realizado.

### Dimensões `classe` / `categoria` / `curso`

As views são quebradas por **`classe`** (grupo fiscal) e **`categoria`** (linha do demonstrativo):

| classe | categoria | O que é | Imposto de serviço? |
|---|---|---|---|
| `POS_GRADUACAO` | `Pós-Graduação` | Pós (curso) | **Sim** |
| `EXTENSAO` | `Extensão` | Extensão (curso) | **Sim** |
| `ADMINISTRATIVO` | `Multa` | Multa de rescisão/atraso | **Não** (receita financeira) |
| `ADMINISTRATIVO` | `Cancelamento` | Cancelamento | **Não** |
| `ADMINISTRATIVO` | `Negociação` | Acordo/negociação | **Não** |

- **`categoria`** é a dimensão pra **abrir as linhas** do demonstrativo (Multa / Cancelamento / Negociação separados).
- **`classe`** é o grupo fiscal: `POS_GRADUACAO + EXTENSAO` = faturamento de curso (tributado); `ADMINISTRATIVO` = financeiro (sem imposto de serviço, régua fiscal a definir). Não é excluído.
- `categoria → classe` é determinístico (1:1). Hoje só `Multa` tem recebimento; `Cancelamento`/`Negociação` aparecem como linha quando tiverem cobrança paga.
- **`curso`** (em `vw_faturamento_eventos`) é o **nome canônico** (4 cursos reais, sem "A VISTA"/"Empresa"/"Recorrente"); no administrativo distingue Multa Pós × Multa Extensão.

### `vw_lucratividade_mensal` — colunas

Grão: **tenant × mês × classe**.

| Coluna | Tipo | Nota |
|---|---|---|
| `tenant_id` | uuid | |
| `tenant_nome` | text | |
| `ano_mes` | text | `'YYYY-MM'` (competência por data de pagamento) |
| `classe` | text | `POS_GRADUACAO` / `EXTENSAO` / `ADMINISTRATIVO` (grupo fiscal) |
| `categoria` | text | `Pós-Graduação` / `Extensão` / `Multa` / `Cancelamento` / `Negociação` (linha do demonstrativo) |
| `faturamento_bruto` | numeric | faturamento reconhecido, **já líquido das reversões** do mês |
| `taxa_voomp` | numeric | |
| `taxa_secretaria` | numeric | = comissão co-produtor |
| `valor_liquido` | numeric | `faturamento_bruto − taxa_voomp − taxa_secretaria` |
| `iss` `pis` `cofins` `irpj` `csll` | numeric | imposto = `valor_liquido × alíquota` (0 para `ADMINISTRATIVO`) |
| `total_impostos` | numeric | |
| `lucratividade` | numeric | `valor_liquido − total_impostos` |

> Pra o total do tenant/mês (todas as classes), **some as linhas** ou filtre a classe desejada.

### `vw_faturamento_eventos` — colunas

`tenant_id, contract_id, voomp_venda_id, product_id, curso, classe, categoria,
evento, competencia (date), ano_mes, valor, taxa_voomp, taxa_secretaria`

`evento ∈ { BOOKING_ASSINATURA, BOOKING_AVISTA, REVERSAO_REEMBOLSO_AVISTA, REVERSAO_CHURN_ASSINATURA }`.
Em reversões, `valor`/`taxa_*` vêm **negativos**.

### `vw_recebimentos_mensal` — colunas (caixa)

Grão: **tenant × mês × tipo_recebimento × classe × categoria**. Competência = `data_pagamento`.

| Coluna | Nota |
|---|---|
| `tenant_id` `tenant_nome` `ano_mes` | |
| `mes_emissao` | **safra** — `'YYYY-MM'` da entrada (assinatura: `data_primeira_venda`; à vista: o próprio mês). Cruze `ano_mes` × `mes_emissao` pro cohort |
| `tipo_recebimento` | **`Nova`** (à vista + entrada P1) · **`Recorrente`** (parcelas 2…N) |
| `classe` `categoria` | mesma dimensão das outras views |
| `qtd` | nº de recebimentos |
| `recebido` | valor recebido (`faturamento_total`, real sem juros) |
| `taxa_voomp` `taxa_secretaria` | splits |
| `valor_liquido` | `recebido − taxa_voomp − taxa_secretaria` (caixa líquido) |

> Recebido = `categoria PAGO` (mesma convenção da CR/cohort). Reembolso/CB são saída e **não** entram aqui.

---

## 5. Snippets prontos

**Demonstrativo de um mês (os dois tenants):**

```ts
// retorna 1 linha por classe (POS_GRADUACAO / EXTENSAO / ADMINISTRATIVO)
const { data, error } = await supabase.schema('fechamento')
  .from('vw_lucratividade_mensal')
  .select('tenant_nome, classe, faturamento_bruto, valor_liquido, total_impostos, lucratividade')
  .eq('ano_mes', '2026-05')
  .order('tenant_nome')

// faturamento de curso = somar POS_GRADUACAO + EXTENSAO; ADMINISTRATIVO é financeiro à parte
```

**Série histórica de um tenant:**

```ts
const { data } = await supabase.schema('fechamento')
  .from('vw_lucratividade_mensal')
  .select('ano_mes, faturamento_bruto, valor_liquido, lucratividade')
  .eq('tenant_id', tenantId)
  .order('ano_mes')
```

**Drill-down dos eventos de um mês (auditar de onde veio o número):**

```ts
const { data } = await supabase.schema('fechamento')
  .from('vw_faturamento_eventos')
  .select('evento, competencia, voomp_venda_id, contract_id, valor, taxa_voomp, taxa_secretaria')
  .eq('ano_mes', '2026-05')
```

**Recebido do mês — fluxo de caixa Nova × Recorrente:**

```ts
const { data } = await supabase.schema('fechamento')
  .from('vw_recebimentos_mensal')
  .select('tenant_nome, tipo_recebimento, categoria, recebido, valor_liquido')
  .eq('ano_mes', '2026-05')
// agrupe por tipo_recebimento (Nova/Recorrente); por classe/categoria pra abrir Pós/Extensão
```

**Cohort — quanto do recebido do mês vem de cada safra:**

```ts
const { data } = await supabase.schema('fechamento')
  .from('vw_recebimentos_mensal')
  .select('mes_emissao, tipo_recebimento, recebido')
  .eq('ano_mes', '2026-06')      // mês recebido
  .order('mes_emissao')
// pivote ano_mes (recebido) × mes_emissao (safra) pro mapa de cohort
```

**Alíquotas vigentes (pra exibir / alimentar um simulador):**

```ts
const { data } = await supabase.schema('fechamento')
  .from('parametros_fiscais')
  .select('imposto, aliquota, vigencia_inicio, vigencia_fim')
  .is('vigencia_fim', null)   // vigentes
```

---

## 6. Pontos de atenção

- **A fotografia é do front.** O banco **não congela** mês. A view recalcula sempre
  sobre a base atual; o snapshot que o front salvar é a verdade congelada de vocês.
  Se a base mudar depois (reabertura/reprocesso), a view diverge do snapshot — isso é esperado.
- **`faturamento_bruto`** na lucratividade já vem **líquido das reversões** de churn/reembolso
  do mês (= `faturamento_liquido` da `vw_faturamento_mensal`).
- **Impostos** não vivem no front: as alíquotas estão em `parametros_fiscais` (versionadas
  por vigência) no banco, pra o mês fechado ser reproduzível. O front pode **simular**
  com outros %, mas o número oficial usa os parâmetros do banco.
- **Não escrever** nessas views (read-only). Qualquer mudança de regra/valor é no
  repo `unipds-banco` (migration revisada pelo mentor do banco).
- **Tenants:** IA `e717e24d-…b0a66783` · Java `70b668e4-…3876929ac850`.

---

## 7. Limitações conhecidas (v1)

- **Data do estorno** usa a data de pagamento original como proxy (exato p/ reembolso no
  mesmo mês; cross-mês exigiria ingerir o extrato de movimentação).
- **Data de saída (churn)** usa o vencimento da 1ª parcela não paga como proxy
  (`contracts.data_encerramento` não é preenchida pela Voomp).
- **Reembolso de parcela isolada** numa assinatura ativa (sem cancelar) não é revertido no v1.
