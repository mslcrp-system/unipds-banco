// ============================================================
// Edge Function: ingest-voomp-xlsx
//
// Le XLSX do bucket voomp-uploads, parse para JSON,
// popula raw_imports + raw_lines, move arquivo para processed/.
//
// Invocacao:
//   POST /functions/v1/ingest-voomp-xlsx
//   Body: { "path": "ia/voomp_ia_2026-05-17.xlsx" }
//         (pasta determina fonte: ia ou java)
// ============================================================

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import * as XLSX from 'https://esm.sh/xlsx@0.18.5';
import { notifyIngestSuccess, notifyIngestDuplicate, notifyIngestError } from '../_shared/discord.ts';

const FONTES: Record<string, { fonte_id: string; nome: string }> = {
  ia: {
    fonte_id: 'fa773a8a-afce-404c-bfde-2671b186ca3b',
    nome:     'Voomp IA',
  },
  java: {
    fonte_id: 'ab644e93-a398-47b0-a88d-d41cf2055d46',
    nome:     'Voomp Java',
  },
};

const BUCKET = 'voomp-uploads';
const BATCH_SIZE = 500;

async function sha256Hex(bytes: Uint8Array): Promise<string> {
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

  let filename = '<desconhecido>';

  try {
    const body = await req.json();
    const path: string = body.path;

    if (!path) {
      return new Response(JSON.stringify({ error: 'path obrigatorio' }), { status: 400 });
    }

    filename = path.split('/').pop() ?? path;
    const pasta = path.split('/')[0]?.toLowerCase();
    const fonte = FONTES[pasta];

    if (!fonte) {
      const erro = `Pasta invalida: ${pasta}. Use ia/ ou java/`;
      await notifyIngestError(filename, erro, 'validacao');
      return new Response(JSON.stringify({ error: erro }), { status: 400 });
    }

    console.log(`[ingest] Iniciando: ${path} (fonte: ${fonte.nome})`);

    // 1. Download
    const { data: fileData, error: dlError } = await supabase.storage
      .from(BUCKET).download(path);
    if (dlError || !fileData) {
      const erro = `Falha download: ${dlError?.message}`;
      await notifyIngestError(filename, erro, 'download');
      return new Response(JSON.stringify({ error: erro }), { status: 500 });
    }
    const bytes = new Uint8Array(await fileData.arrayBuffer());
    console.log(`[ingest] Download OK: ${bytes.length} bytes`);

    // 2. SHA256
    const sha = await sha256Hex(bytes);
    console.log(`[ingest] SHA256: ${sha}`);

    // 3. Dedup
    const { data: existente } = await supabase
      .schema('unipds')
      .from('raw_imports')
      .select('import_id, total_linhas, imported_at')
      .eq('sha256_hash', sha)
      .maybeSingle();

    if (existente) {
      await notifyIngestDuplicate(filename, existente.import_id, existente.total_linhas, existente.imported_at);
      return new Response(JSON.stringify({
        status: 'already_processed',
        import_id: existente.import_id,
        total_linhas: existente.total_linhas,
      }), { status: 200, headers: { 'Content-Type': 'application/json' } });
    }

    // 4. Parse XLSX
    const workbook = XLSX.read(bytes, { type: 'array', cellDates: true });
    const sheetName = workbook.SheetNames[0];
    const sheet = workbook.Sheets[sheetName];
    const rows = XLSX.utils.sheet_to_json(sheet, { defval: '', raw: false });
    console.log(`[ingest] Parse OK: ${rows.length} linhas`);

    if (rows.length === 0) {
      const erro = 'XLSX sem linhas de dados';
      await notifyIngestError(filename, erro, 'parse');
      return new Response(JSON.stringify({ error: erro }), { status: 400 });
    }

    // 5. INSERT raw_imports
    const { data: imp, error: impError } = await supabase
      .schema('unipds')
      .from('raw_imports')
      .insert({
        fonte_id:     fonte.fonte_id,
        nome_arquivo: filename,
        sha256_hash:  sha,
        total_linhas: rows.length,
        status:       'processing',
      })
      .select('import_id')
      .single();

    if (impError || !imp) {
      const erro = `INSERT raw_imports: ${impError?.message}`;
      await notifyIngestError(filename, erro, 'raw_imports');
      return new Response(JSON.stringify({ error: erro }), { status: 500 });
    }

    console.log(`[ingest] raw_imports criado: ${imp.import_id}`);

    // 6. BULK INSERT raw_lines em chunks
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
        await notifyIngestError(filename, `batch ${i}: ${chunkError.message}`, 'raw_lines');
        return new Response(JSON.stringify({ error: chunkError.message }), { status: 500 });
      }
      inserted += chunk.length;
    }
    console.log(`[ingest] ${inserted} raw_lines inseridas`);

    await supabase.schema('unipds').from('raw_imports')
      .update({ status: 'done', processadas: inserted })
      .eq('import_id', imp.import_id);

    // 7. Move arquivo para processed/
    const destPath = `processed/${pasta}/${filename}`;
    const { error: moveError } = await supabase.storage
      .from(BUCKET).move(path, destPath);
    if (moveError) {
      console.warn(`[ingest] Move falhou: ${moveError.message}`);
    }

    // 8. Discord sucesso
    await notifyIngestSuccess(filename, fonte.nome, inserted, imp.import_id);

    return new Response(JSON.stringify({
      status: 'success',
      import_id: imp.import_id,
      fonte: fonte.nome,
      total_linhas: inserted,
      moved_to: destPath,
    }), { status: 200, headers: { 'Content-Type': 'application/json' } });

  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('[ingest] CRASH:', msg);
    await notifyIngestError(filename, msg, 'exception');
    return new Response(JSON.stringify({ error: msg }), { status: 500 });
  }
});
