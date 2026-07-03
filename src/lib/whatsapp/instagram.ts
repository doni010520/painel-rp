import type { Channel } from "@/lib/types";
import type {
  ChannelProvider,
  ConnectResult,
  SendMediaParams,
  SendTextParams,
  InboundMessage,
} from "./types";

// Instagram Messaging API (caso de uso "Gerenciar mensagens e conteúdo no Instagram").
// Base graph.instagram.com para o setup com login do Instagram. As DMs chegam pelo
// MESMO webhook da Meta (object: "instagram", formato Messenger entry[].messaging[]).
const IG_VER = process.env.INSTAGRAM_GRAPH_VERSION || "v23.0";
const IG_BASE = (process.env.INSTAGRAM_GRAPH_BASE || "https://graph.instagram.com") + "/" + IG_VER;

interface IgCreds {
  ig_id?: string; // ID da conta Instagram profissional (é o recipient.id nos webhooks)
  access_token?: string; // IG User access token (instagram_business_manage_messages)
}

export class InstagramProvider implements ChannelProvider {
  private igId?: string;
  private token?: string;

  constructor(channel: Channel) {
    const c = channel.credentials as IgCreds;
    this.igId = c?.ig_id ?? channel.external_id ?? undefined;
    this.token = c?.access_token || process.env.INSTAGRAM_ACCESS_TOKEN;
  }

  private async api(path: string, body: unknown) {
    const res = await fetch(`${IG_BASE}/${path}`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error(`Instagram ${path} -> ${res.status} ${await res.text()}`);
    return res.json();
  }

  // Não há QR: "conectar" é validar as credenciais.
  async connect(_phone?: string): Promise<ConnectResult> {
    if (!this.igId || !this.token) return { status: "error" };
    return { status: "connected", externalId: this.igId };
  }

  async status(): Promise<Channel["status"]> {
    return this.igId && this.token ? "connected" : "disconnected";
  }

  /** Envia texto para um usuário (IGSID = id do remetente recebido no webhook). */
  async sendText({ to, text }: SendTextParams) {
    const r = await this.api(`${this.igId}/messages`, {
      recipient: { id: to },
      message: { text },
    });
    return { externalId: r?.message_id };
  }

  /** Envia mídia por URL (imagem/áudio/vídeo). */
  async sendMedia({ to, url, kind }: SendMediaParams) {
    const type = kind === "document" ? "file" : kind === "sticker" ? "image" : kind;
    const r = await this.api(`${this.igId}/messages`, {
      recipient: { id: to },
      message: { attachment: { type, payload: { url, is_reusable: true } } },
    });
    return { externalId: r?.message_id };
  }

  /** Nome/username do contato Instagram pelo IGSID (best-effort). */
  async getChatInfo(igsid: string): Promise<{ name?: string; image?: string }> {
    try {
      const res = await fetch(
        `${IG_BASE}/${igsid}?fields=name,username,profile_pic&access_token=${this.token}`,
      );
      if (!res.ok) return {};
      const j = await res.json();
      return { name: j?.name || j?.username, image: j?.profile_pic };
    } catch {
      return {};
    }
  }
}

/**
 * Normaliza o webhook do Instagram (object:"instagram") em mensagens internas.
 * Formato Messenger: entry[].messaging[] com sender.id (IGSID) e message.
 * Ignora ecos do próprio negócio (is_echo) e reações/leituras.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function parseInstagramWebhook(payload: any): InboundMessage[] {
  if (payload?.object !== "instagram") return [];
  const out: InboundMessage[] = [];
  for (const entry of payload?.entry ?? []) {
    const igAccountId = String(entry?.id ?? "");
    for (const m of entry?.messaging ?? []) {
      const msg = m?.message;
      if (!msg || msg.is_echo) continue; // eco de mensagem enviada pelo negócio
      const from = String(m?.sender?.id ?? "");
      if (!from) continue;
      const att = Array.isArray(msg.attachments) ? msg.attachments[0] : undefined;
      let contentType: InboundMessage["contentType"] = "text";
      let mediaUrl: string | undefined;
      let body: string | undefined = msg.text;
      if (att) {
        const t = String(att.type || "").toLowerCase();
        contentType = t === "image" ? "image" : t === "audio" ? "audio" : t === "video" ? "video" : "document";
        mediaUrl = att?.payload?.url;
      }
      out.push({
        channelExternalId: igAccountId, // = external_id do canal (ig_id)
        from,
        contentType,
        body,
        mediaUrl,
        externalId: msg.mid,
        timestamp: m?.timestamp ? String(m.timestamp) : undefined,
      });
    }
  }
  return out;
}
