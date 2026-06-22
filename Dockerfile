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
# ANON key embutida no build. É PÚBLICA por design (vive no navegador; o RLS é quem
# protege os dados), então pode ir no git/imagem — assim o login funciona sem depender
# de env de runtime no EasyPanel. Para trocar de projeto, sobrescreva via --build-arg.
ARG NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNrYWNzd3dmYmJkYnRhYmdxc3F5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM2ODU5NjcsImV4cCI6MjA4OTI2MTk2N30.G4f7bqzj14MDro8RgKpqGxWIVhmZwjnI7hT_SNgZz2o
ARG NEXT_PUBLIC_META_APP_ID
ARG NEXT_PUBLIC_META_CONFIG_ID
ARG NEXT_PUBLIC_META_GRAPH_VERSION
# Commit que originou a imagem (mostrado em /api/version).
ARG GIT_SHA=dev
ENV NEXT_PUBLIC_SUPABASE_URL=$NEXT_PUBLIC_SUPABASE_URL \
    NEXT_PUBLIC_SUPABASE_ANON_KEY=$NEXT_PUBLIC_SUPABASE_ANON_KEY \
    NEXT_PUBLIC_META_APP_ID=$NEXT_PUBLIC_META_APP_ID \
    NEXT_PUBLIC_META_CONFIG_ID=$NEXT_PUBLIC_META_CONFIG_ID \
    NEXT_PUBLIC_META_GRAPH_VERSION=$NEXT_PUBLIC_META_GRAPH_VERSION \
    GIT_SHA=$GIT_SHA
RUN npm run build

FROM node:20-alpine AS runner
WORKDIR /app
ARG GIT_SHA=dev
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PORT=3000 HOSTNAME=0.0.0.0 GIT_SHA=$GIT_SHA
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
EXPOSE 3000
CMD ["node", "server.js"]
