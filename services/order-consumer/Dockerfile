FROM node:20-bookworm AS builder
WORKDIR /app
COPY package.json ./
COPY packages/shared/package.json packages/shared/
COPY services/order-consumer/package.json services/order-consumer/
COPY tsconfig.base.json ./
COPY packages/shared packages/shared
COPY services/order-consumer services/order-consumer
RUN npm install
RUN npm run build -w @mq-lab/shared
RUN npm run build -w @mq-lab/order-consumer

FROM node:20-bookworm
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends wget curl ca-certificates \
  && rm -rf /var/lib/apt/lists/*
COPY docker/install-mq-client.sh /tmp/install-mq-client.sh
RUN chmod 755 /tmp/install-mq-client.sh && /tmp/install-mq-client.sh && rm /tmp/install-mq-client.sh
ENV LD_LIBRARY_PATH=/opt/mqm/lib64
ENV MQ_INSTALLATION_PATH=/opt/mqm
RUN addgroup --gid 1001 nodejs && adduser --uid 1001 --gid 1001 --disabled-password nodejs
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/packages/shared/dist ./packages/shared/dist
COPY --from=builder /app/packages/shared/package.json ./packages/shared/
COPY --from=builder /app/services/order-consumer/dist ./services/order-consumer/dist
COPY --from=builder /app/services/order-consumer/package.json ./services/order-consumer/
USER nodejs
WORKDIR /app/services/order-consumer
ENV NODE_ENV=production
EXPOSE 8081
HEALTHCHECK CMD wget -qO- http://localhost:8081/health || exit 1
CMD ["node", "-r", "@mq-lab/shared/instrumentation", "dist/index.js"]
