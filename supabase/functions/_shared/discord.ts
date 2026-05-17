const WEBHOOK_URL = Deno.env.get('DISCORD_WEBHOOK_URL');

async function send(payload: Record<string, unknown>): Promise<void> {
  if (!WEBHOOK_URL) return;
  try {
    await fetch(WEBHOOK_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
  } catch {
    // Discord nao eh critico — ignora falhas de notificacao
  }
}

export async function sendDiscord(message: string): Promise<void> {
  await send({ content: message });
}

// ── ingest-voomp-xlsx ─────────────────────────────────────────────────────────

export async function notifyIngestSuccess(filename: string, fonte: string, total_linhas: number, import_id: string): Promise<void> {
  await send({
    content: `✅ **ingest-voomp-xlsx** — ${filename}`,
    embeds: [{
      title: `Ingestão concluída — ${fonte}`, color: 0x4CAF50,
      fields: [
        { name: 'Arquivo',      value: filename,                                              inline: false },
        { name: 'Fonte',        value: fonte,                                                 inline: true },
        { name: 'Linhas',       value: String(total_linhas),                                  inline: true },
        { name: 'import_id',    value: `\`${import_id}\``,                                    inline: false },
        { name: 'Próximo passo', value: '`SELECT * FROM unipds.processar_raw_lines(\'full\');`', inline: false },
      ],
    }],
  });
}

export async function notifyIngestDuplicate(filename: string, import_id: string, total_linhas: number, imported_at: string): Promise<void> {
  await send({
    content: `⚠️ **ingest-voomp-xlsx** — reingestão ignorada`,
    embeds: [{
      title: `Arquivo já processado anteriormente`, color: 0xFFAA00,
      fields: [
        { name: 'Arquivo',       value: filename,             inline: false },
        { name: 'Processado em', value: imported_at,          inline: true },
        { name: 'Linhas',        value: String(total_linhas), inline: true },
        { name: 'import_id',     value: `\`${import_id}\``,   inline: false },
      ],
    }],
  });
}

export async function notifyIngestError(filename: string, error: string, etapa: string): Promise<void> {
  await send({
    content: `🔴 **ingest-voomp-xlsx** — erro em ${filename}`,
    embeds: [{
      title: `Falha na ingestão`, color: 0xE05454,
      fields: [
        { name: 'Arquivo',   value: filename,                          inline: false },
        { name: 'Etapa',     value: etapa,                             inline: true },
        { name: 'Erro',      value: `\`${error.slice(0, 300)}\``,      inline: false },
        { name: 'Timestamp', value: new Date().toISOString(),          inline: true },
      ],
    }],
  });
}
