const WEBHOOK_URL = Deno.env.get('DISCORD_WEBHOOK_URL');

export async function sendDiscord(message: string): Promise<void> {
  if (!WEBHOOK_URL) return;
  try {
    await fetch(WEBHOOK_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content: message }),
    });
  } catch {
    // Discord nao eh critico — ignora falhas de notificacao
  }
}
