import { Scroll } from "@/components/scroll";
import { PageHeader } from "@/components/ui";
import { TicketsClient } from "./tickets-client";

export const dynamic = "force-dynamic";

export default function TicketsPage() {
  return (
    <Scroll>
      <PageHeader
        title="Tickets"
        subtitle="Fila de atendimentos escalados pelo bot (notificar equipe) + métricas."
      />
      <TicketsClient />
    </Scroll>
  );
}
