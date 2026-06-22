import type { Channel, ConversationOverview, Message, Department, Tag, QuickReply, Profile } from "@/lib/types";

// Dados de exemplo usados no "modo preview" (sem Supabase configurado),
// inspirados na conta real para a tela ficar realista.
export const MOCK_CHANNELS: Channel[] = [
  mk("Royal Print — Atendimento", "uazapi", "5581991110000", "connected"),
  mk("Royal Print — Vendas", "uazapi", "5581991110010", "connected"),
  mk("Royal Print — Assistência Técnica", "uazapi", "5581991110020", "connected"),
  mk("Royal Print — API Oficial", "meta_cloud", "5581991110030", "connecting"),
];

function mk(
  name: string,
  type: Channel["type"],
  phone: string,
  status: Channel["status"],
): Channel {
  return {
    id: crypto.randomUUID(),
    organization_id: "preview",
    name,
    type,
    phone,
    status,
    external_id: null,
    credentials: {},
    created_at: new Date().toISOString(),
  };
}

export const PREVIEW_MODE = !process.env.NEXT_PUBLIC_SUPABASE_URL;

export const MOCK_DEPARTMENTS: Department[] = [
  { id: "d1", organization_id: "preview", name: "Assistência Técnica", color: "#00a8ff", created_at: "" },
  { id: "d2", organization_id: "preview", name: "Financeiro", color: "#f59e0b", created_at: "" },
  { id: "d3", organization_id: "preview", name: "Gráfica / Vendas", color: "#10b981", created_at: "" },
];

export const MOCK_TAGS: Tag[] = [
  { id: "t1", organization_id: "preview", name: "Resolvido", color: "#10b981", scope: "conversation", created_at: "" },
  { id: "t2", organization_id: "preview", name: "Aguardando pagamento", color: "#f59e0b", scope: "conversation", created_at: "" },
  { id: "t3", organization_id: "preview", name: "VIP", color: "#8b5cf6", scope: "contact", created_at: "" },
  { id: "t4", organization_id: "preview", name: "Almoço", color: "#6b7280", scope: "status", created_at: "" },
];

export const MOCK_QUICK_REPLIES: QuickReply[] = [
  { id: "q1", organization_id: "preview", title: "Saudação", content: "Olá! Bem-vindo(a) à Royal Print! 🖨️ Como posso te ajudar hoje?", shortcut: "/oi", kind: "model", created_at: "" },
  { id: "q2", organization_id: "preview", title: "Horário", content: "Atendemos de seg a sex, 7:30 às 18h, e sáb das 8h às 13h.", shortcut: "/horario", kind: "model", created_at: "" },
  { id: "q3", organization_id: "preview", title: "Localização", content: "Estamos na Av. Hist. Pereira Costa, 447 — Cabo de Santo Agostinho/PE.", shortcut: "/local", kind: "model", created_at: "" },
];

export const MOCK_AGENTS: Profile[] = [
  { id: "u1", organization_id: "preview", name: "Tainá Borges", email: "taina@royalprint.com.br", role: "agent", department_id: "d1", avatar_url: null, status: "online", whatsapp: null, notify: true, created_at: "" },
  { id: "u2", organization_id: "preview", name: "Luana Santos", email: "luana@royalprint.com.br", role: "supervisor", department_id: "d2", avatar_url: null, status: "away", whatsapp: null, notify: true, created_at: "" },
  { id: "u3", organization_id: "preview", name: "ADONIAS SOUZA", email: "adonias@royalprint.com.br", role: "admin", department_id: null, avatar_url: null, status: "offline", whatsapp: null, notify: true, created_at: "" },
];

// ---------- Conversas e mensagens (modo preview) ----------
const ago = (min: number) => new Date(Date.now() - min * 60000).toISOString();

export const MOCK_CONVERSATIONS: ConversationOverview[] = [
  conv("Joana Lima", "5581991110001", "Royal Print — Assistência Técnica", "uazapi", "open", "Boa tarde! Minha impressora não está puxando papel.", 2),
  conv("Carlos Eduardo", "5581991110002", "Royal Print — Vendas", "uazapi", "queued", "Quanto fica 100 cartões de visita?", 11),
  conv("Maria Santos", "5581991110003", "Royal Print — Atendimento", "uazapi", "open", "Já fiz o pagamento, pode confirmar?", 25),
  conv("Pedro Alves", "5581991110004", "Royal Print — Assistência Técnica", "uazapi", "bot", "Minha OS 886 já está pronta?", 40),
  conv("Lucia Ferreira", "5581991110005", "Royal Print — Vendas", "uazapi", "closed", "Obrigada, resolvido!", 180),
];

export const MOCK_MESSAGES: Record<string, Message[]> = {
  [MOCK_CONVERSATIONS[0].id]: [
    msg(MOCK_CONVERSATIONS[0].id, "in", "contact", "Boa tarde!", 6),
    msg(MOCK_CONVERSATIONS[0].id, "out", "agent", "Boa tarde, Joana! Bem-vinda à Royal Print 🖨️ Como posso ajudar?", 5),
    msg(MOCK_CONVERSATIONS[0].id, "in", "contact", "Minha impressora HP não está puxando papel.", 2),
  ],
  [MOCK_CONVERSATIONS[1].id]: [
    msg(MOCK_CONVERSATIONS[1].id, "in", "contact", "Quanto fica 100 cartões de visita?", 11),
  ],
  [MOCK_CONVERSATIONS[2].id]: [
    msg(MOCK_CONVERSATIONS[2].id, "in", "contact", "Já fiz o pagamento, pode confirmar?", 25),
  ],
};

function conv(
  name: string,
  phone: string,
  channelName: string,
  channelType: Channel["type"],
  status: ConversationOverview["status"],
  last: string,
  minAgo: number,
): ConversationOverview {
  const id = crypto.randomUUID();
  return {
    id,
    organization_id: "preview",
    status,
    assigned_user_id: null,
    department_id: null,
    channel_id: "preview",
    contact_id: crypto.randomUUID(),
    protocol: null,
    last_message_at: ago(minAgo),
    opened_at: ago(minAgo + 10),
    closed_at: null,
    created_at: ago(minAgo + 10),
    contact_name: name,
    contact_phone: phone,
    contact_avatar: null,
    channel_name: channelName,
    channel_type: channelType,
    last_message_body: last,
    last_message_type: "text",
    last_message_direction: "in",
  };
}

function msg(
  conversationId: string,
  direction: Message["direction"],
  sender: Message["sender_type"],
  body: string,
  minAgo: number,
): Message {
  return {
    id: crypto.randomUUID(),
    organization_id: "preview",
    conversation_id: conversationId,
    direction,
    sender_type: sender,
    sender_id: null,
    content_type: "text",
    body,
    media_url: null,
    status: "delivered",
    external_id: null,
    created_at: ago(minAgo),
  };
}
