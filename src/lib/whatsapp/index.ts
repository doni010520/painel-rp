import type { Channel } from "@/lib/types";
import type { ChannelProvider } from "./types";
import { UazapiProvider } from "./uazapi";
import { MetaProvider } from "./meta";
import { InstagramProvider } from "./instagram";

export function getProvider(channel: Channel): ChannelProvider {
  switch (channel.type) {
    case "uazapi":
      return new UazapiProvider(channel);
    case "meta_cloud":
      return new MetaProvider(channel);
    case "instagram":
      return new InstagramProvider(channel);
    default:
      throw new Error(`Tipo de canal não suportado: ${channel.type}`);
  }
}

export * from "./types";
