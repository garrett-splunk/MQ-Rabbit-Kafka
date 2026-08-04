FROM node:20-bookworm AS builder
WORKDIR /app
COPY package.json ./
COPY packages/shared/package.json packages/shared/
COPY services/inventory-service/package.json services/inventory-service/
COPY tsconfig.base.json ./
COPY packages/shared packages/shared
COPY services/inventory-service services/inventory-service
RUN npm install
RUN npm run build -w @mq-lab/shared
RUN npm run build -w @mq-lab/inventory-service

FROM node:20-bookworm
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends wget curl ca-certificates \
  && rm -rf /var/lib/apt/lists/*
RUN addgroup --gid 1001 nodejs && adduser --uid 1001 --gid 1001 --disabled-password nodejs
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/packages/shared/dist ./packages/shared/dist
COPY --from=builder /app/packages/shared/package.json ./packages/shared/
COPY --from=builder /app/services/inventory-service/dist ./services/inventory-service/dist
COPY --from=builder /app/services/inventory-service/package.json ./services/inventory-service/
USER nodejs
WORKDIR /app/services/inventory-service
ENV NODE_ENV=production
EXPOSE 8082
HEALTHCHECK CMD wget -qO- http://localhost:8082/health || exit 1
CMD ["node", "-r", "@mq-lab/shared/instrumentation", "dist/index.js"]
