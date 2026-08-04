import express from 'express';
import { trace, SpanStatusCode } from '@opentelemetry/api';
import { bootstrapService, createLogger } from '@mq-lab/shared';
import { connect, loadMqConfig, openQueue, getMessage, disconnect, MQC } from './mq.js';

const SERVICE_NAME = 'order-consumer';
const log = createLogger(SERVICE_NAME);
const tracer = trace.getTracer(SERVICE_NAME);
const inventoryUrl = process.env.INVENTORY_SERVICE_URL || 'http://inventory-service:8082';

const app = express();
bootstrapService({ app, serviceName: SERVICE_NAME });

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: SERVICE_NAME, consuming: consumerRunning });
});

let consumerRunning = true;

async function consumeLoop(): Promise<void> {
  const queueName = process.env.MQ_REQUEST_QUEUE || 'ORDER.REQ';
  const config = loadMqConfig();

  while (consumerRunning) {
    let hConn;
    try {
      hConn = await connect(config);
      const hQueue = await openQueue(
        hConn,
        queueName,
        MQC.MQOO_INPUT_AS_Q_DEF | MQC.MQOO_FAIL_IF_QUIESCING
      );

      while (consumerRunning) {
        await tracer.startActiveSpan('mq.get.order', async (span) => {
          span.setAttribute('messaging.system', 'ibmmq');
          span.setAttribute('messaging.destination.name', queueName);
          try {
            const msg = await getMessage(hQueue, 5000);
            span.setAttribute('messaging.message_id', msg.msgId);
            const order = JSON.parse(msg.body) as Record<string, unknown>;
            log.info('Order message consumed from IBM MQ', {
              queue: queueName,
              msgId: msg.msgId,
              correlationIdMq: msg.correlId,
              orderId: order.orderId,
              productId: order.productId,
            });

            await tracer.startActiveSpan('inventory.fulfill', async (fulfillSpan) => {
              const orderId = String(order.orderId ?? msg.correlId ?? 'unknown');
              const productId = String(order.productId ?? 'SKU-100');
              const quantity = Number(order.quantity ?? 1);
              fulfillSpan.setAttribute('order.id', orderId);
              fulfillSpan.setAttribute('inventory.product_id', productId);
              try {
                const fulfillRes = await fetch(`${inventoryUrl}/fulfill`, {
                  method: 'POST',
                  headers: {
                    'Content-Type': 'application/json',
                    'X-Correlation-Id': orderId,
                  },
                  body: JSON.stringify({ orderId, productId, quantity }),
                });
                if (!fulfillRes.ok) {
                  fulfillSpan.setStatus({
                    code: SpanStatusCode.ERROR,
                    message: `inventory fulfill ${fulfillRes.status}`,
                  });
                  log.warn('Inventory fulfill failed', { orderId, status: fulfillRes.status });
                }
              } catch (err) {
                const error = err as Error;
                fulfillSpan.recordException(error);
                fulfillSpan.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
                log.warn('Inventory fulfill error', { orderId, error: error.message });
              } finally {
                fulfillSpan.end();
              }
            });
          } catch (err) {
            const error = err as Error & { mqrc?: number };
            if (error.mqrc === MQC.MQRC_NO_MSG_AVAILABLE) {
              span.setStatus({ code: SpanStatusCode.OK });
              return;
            }
            span.recordException(error);
            span.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
            log.warn('MQ GET failed', {
              queue: queueName,
              error: { message: error.message, type: error.name },
            });
            consumerRunning = false;
          } finally {
            span.end();
          }
        });
      }

      await disconnect(hConn);
    } catch (err) {
      const error = err as Error;
      log.error('Consumer connection failed', {
        error: { message: error.message, stack: error.stack, type: error.name },
      });
      await new Promise((r) => setTimeout(r, 5000));
    }
  }
}

const port = Number(process.env.PORT || 8081);
app.listen(port, () => {
  log.info('Order consumer health endpoint listening', { port });
  consumeLoop().catch((err) => {
    log.fatal('Consumer loop exited', { error: { message: (err as Error).message } });
    process.exit(1);
  });
});

process.on('SIGTERM', () => {
  consumerRunning = false;
});
