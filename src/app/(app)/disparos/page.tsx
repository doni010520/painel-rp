import { Scroll } from "@/components/scroll";
import { PageHeader } from "@/components/ui";
import { DisparosClient } from "./disparos-client";

export const dynamic = "force-dynamic";

export default function DisparosPage() {
  return (
    <Scroll>
      <PageHeader
        title="Disparos"
        subtitle="Envio em massa de mídia + legenda pelo WhatsApp (imediato ou agendado)."
      />
      <DisparosClient />
    </Scroll>
  );
}
