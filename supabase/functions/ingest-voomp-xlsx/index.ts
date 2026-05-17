// ============================================================
// Edge Function: ingest-voomp-xlsx
//
// Le XLSX do bucket voomp-uploads, faz parse para JSON,
// popula raw_imports + raw_lines, move o arquivo para processed/.
//
// Invocacao:
//   POST /functions/v1/ingest-voomp-xlsx
//   Body: { "path": "ia/voomp_ia_2026-05-17.xlsx" }
//         (path relativo ao bucket; pasta determina fonte)
//
// Fluxo:
//   1. Identifica fonte pela pasta (ia/ ou java/)
//   2. Download do bucket
//   3. Calcula SHA256
//   4. Verifica raw_imports.sha256_hash (dedup)
//   5. Parse XLSX -> array JSON
//   6. INSERT raw_imports + BULK raw_lines
//   7. Move arquivo para processed/<fonte>/
//   8. Notifica Discord
//   9. Retorna stats
// ============================================================

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import * as XLSX from 'https://esm.sh/xlsx@0.18.5';
import { sendDiscord } from '../_shared/discord.ts';

const FONTES: Record<string, { fonte_id: string; tenant_id: string; nome: string }> = {
  ia: {
    fonte_id:  'fa773a8a-afce-404c-bfde-2671b186ca3b',
    tenant_id: 'e717e24d-fb30-4ed0-83d3-bb8ea0b66783',
    nome:      'Voomp IA',
  },
  java: {
    fonte_id:  'ab644e93-a398-47b0-a88d-d41cf2055d46',
    tenant_id: '70b668e4-be85-459b-8dbb-3876929ac850',
    nome:      'Voomp Java',
  },
};

const BUCKET = 'voomp-uploads';
const BATCH_SIZE = 500;

async function sha256(bytes: Uint8Array): Promise<string> {
  const hash = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(hash))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  try {
    const body = await req.json();
    const path: string = body.path;

    if (!path) {
      return new Response(JSON.stringify({ error: 'path obrigatorio' }), { status: 400 });
    }

    // 1. Identifica fonte pela pasta
    const pasta = path.split('/')[0]?.toLowerCase();
    const fonte = FONTES[pasta];
    if (!fonte) {
      const erro = `Pasta invalida: ${pasta}. Use ia/ ou java/`;
      await sendDiscord(`❌ Ingestao falhou: ${erro}`);
      return new Response(JSON.stringify({ error: erro }), { status: 400 });
    }

    const filename = path.split('/').pop()!;
    console.log(`[ingest] Iniciando: ${path} (fonte: ${fonte.nome})`);

    // 2. Download do bucket
    const { data: fileData, error: dlError } = await supabase.storage
      .from(BUCKET).download(path);
    if (dlError || !fileData) {
      const erro = `Falha no download: ${dlError?.message}`;
      await sendDiscord(`❌ Ingestao falhou (${filename}): ${erro}`);
      return new Response(JSON.stringify({ error: erro }), { status: 500 });
    }

    const bytes = new Uint8Array(await fileData.arrayBuffer());
    console.log(`[ingest] Download OK: ${bytes.length} bytes`);

    // 3. SHA256
    const sha = await sha256(bytes);
    console.log(`[ingest] SHA256: ${sha}`);

    // 4. Dedup
    const { data: existente } = await supabase
      .schema('unipds')
      .from('raw_imports')
      .select('import_id, total_linhas, imported_at')
      .eq('sha256_hash', sha)
      .maybeSingle();

    if (existente) {
      const msg = `Arquivo ja processado em ${existente.imported_at} (import_id=${existente.import_id}, ${existente.total_linhas} linhas). Ignorando.`;
      console.log(`[ingest] ${msg}`);
      await sendDiscord(`⚠️ Reingestao ignorada (${filename}): ${msg}`);
      return new Response(JSON.stringify({
        status: 'already_processed',
        import_id: existente.import_id,
        total_linhas: existente.total_linhas,
      }), { status: 200 });
    }

    // 5. Parse XLSX
    const workbook = XLSX.read(bytes, { type: 'array', cellDates: true });
    const sheetName = workbook.SheetNames[0];
    const sheet = workbook.Sheets[sheetName];
    const rows = XLSX.utils.sheet_to_json(sheet, { defval: '', raw: false });
    console.log(`[ingest] Parse OK: ${rows.length} linhas`);

    if (rows.length === 0) {
      const erro = 'XLSX sem linhas de dados';
      await sendDiscord(`❌ Ingestao falhou (${filename}): ${erro}`);
      return new Response(JSON.stringify({ error: erro }), { status: 400 });
    }

    // 6a. INSERT raw_imports
    const { data: imp, error: impError } = await supabase
      .schema('unipds')
      .from('raw_imports')
      .insert({
        fonte_id:    fonte.fonte_id,
        nome_arquivo: filename,
        sha256_hash:  sha,
        total_linhas: rows.length,
        status:       'processing',
      })
      .select('import_id')
      .single();

    if (impError || !imp) {
      const erro = `Falha INSERT raw_imports: ${impError?.message}`;
      await sendDiscord(`❌ Ingestao falhou (${filename}): ${erro}`);
      return new Response(JSON.stringify({ error: erro }), { status: 500 });
    }

    console.log(`[ingest] raw_imports criado: ${imp.import_id}`);

    // 6b. BULK INSERT raw_lines em chunks
    let inserted = 0;
    for (let i = 0; i < rows.length; i += BATCH_SIZE) {
      const chunk = rows.slice(i, i + BATCH_SIZE).map(r => ({
        import_id: imp.import_id,
        payload:   r,
      }));
      const { error: chunkError } = await supabase
        .schema('unipds')
        .from('raw_lines')
        .insert(chunk);
      if (chunkError) {
        await supabase.schema('unipds').from('raw_imports')
          .update({ status: 'error', erros: chunkError.message })
          .eq('import_id', imp.import_id);
        await sendDiscord(`❌ Ingestao falhou (${filename}) no batch ${i}: ${chunkError.message}`);
        return new Response(JSON.stringify({ error: chunkError.message }), { status: 500 });
      }
      inserted += chunk.length;
    }
    console.log(`[ingest] ${inserted} raw_lines inseridas`);

    // Atualiza status final
    await supabase.schema('unipds').from('raw_imports')
      .update({ status: 'done', processadas: inserted })
      .eq('import_id', imp.import_id);

    // 7. Move arquivo para processed/
    const destPath = `processed/${pasta}/${filename}`;
    const { error: moveError } = await supabase.storage
      .from(BUCKET).move(path, destPath);
    if (moveError) {
      // Nao critico - apenas avisa
      console.warn(`[ingest] Move falhou: ${moveError.message}`);
      await sendDiscord(`⚠️ Ingestao OK mas falhou ao mover arquivo (${filename}): ${moveError.message}`);
    }

    // 8. Discord sucesso
    await sendDiscord(
      `✅ Ingestao OK: **${filename}** (${fonte.nome})\n` +
      `• ${inserted} linhas processadas\n` +
      `• import_id: \`${imp.import_id}\`\n` +
      `• Proximo passo: \`SELECT * FROM unipds.processar_raw_lines('full');\``
    );

    return new Response(JSON.stringify({
      status: 'success',
      import_id: imp.import_id,
      fonte: fonte.nome,
      total_linhas: inserted,
      moved_to: destPath,
    }), { status: 200, headers: { 'Content-Type': 'application/json' } });

  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('[ingest] ERRO:', msg);
    await sendDiscord(`❌ Ingestao crashou: ${msg}`);
    return new Response(JSON.stringify({ error: msg }), { status: 500 });
  }
});
