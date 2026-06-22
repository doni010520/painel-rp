# Build off-server (GitHub Actions) → imagem self-contained (Next standalone).
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
# Variáveis NEXT_PUBLIC_* são embutidas no bundle em build-time (são públicas).
# URL e anon key do Supabase têm DEFAULT aqui (são públicas por design) para o build
# ser self-contained no EasyPanel — sem precisar configurar build args. Para trocar de
# projeto Supabase, sobrescreva via --build-arg ou edite os defaults abaixo.
ARG NEXT_PUBLIC_SUPABASE_URL=https://skacswwfbbdbtabgqsqy.supabase.co
# A ANON key NÃO precisa ser embutida no build: o layout injeta URL+anon em runtime
# (force-dynamic) a partir das env vars do EasyPanel. Este placeholder só evita build
# vazio; o valor real chega em runtime via NEXT_PUBLIC_SUPABASE_ANON_KEY.
ARG NEXT_PUBLIC_SUPABASE_ANON_KEY=set-at-runtime
ARG NEXT_PUBLIC_META_APP_ID
ARG NEXT_PUBLIC_META_CONFIG_ID
ARG NEXT_PUBLIC_META_GRAPH_VERSION
ENV NEXT_PUBLIC_SUPABASE_URL=$NEXT_PUBLIC_SUPABASE_URL \
    NEXT_PUBLIC_SUPABASE_ANON_KEY=$NEXT_PUBLIC_SUPABASE_ANON_KEY \
    NEXT_PUBLIC_META_APP_ID=$NEXT_PUBLIC_META_APP_ID \
    NEXT_PUBLIC_META_CONFIG_ID=$NEXT_PUBLIC_META_CONFIG_ID \
    NEXT_PUBLIC_META_GRAPH_VERSION=$NEXT_PUBLIC_META_GRAPH_VERSION
RUN npm run build

FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PORT=3000 HOSTNAME=0.0.0.0
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
EXPOSE 3000
CMD ["node", "server.js"]
