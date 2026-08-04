import express from 'express';
import { trace, SpanStatusCode } from '@opentelemetry/api';
import {
  bootstrapService,
  useServiceErrorHandler,
  asyncHandler,
  getCorrelationId,
  createLogger,
} from '@mq-lab/shared';
import { connect, loadMqConfig, openQueue, putMessage, disconnect, MQC } from './mq.js';

const SERVICE_NAME = 'order-producer';
const log = createLogger(SERVICE_NAME);
const tracer = trace.getTracer(SERVICE_NAME);
const inventoryUrl = process.env.INVENTORY_SERVICE_URL || 'http://inventory-service:8082';

const app = express();
app.use(express.json());

bootstrapService({ app, serviceName: SERVICE_NAME });

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: SERVICE_NAME });
});

app.post(
  '/orders',
  asyncHandler(async (req, res) => {
    const correlationId = getCorrelationId(req);
    const { productId, quantity } = req.body as { productId?: string; quantity?: number };

    if (!productId || typeof quantity !== 'number' || quantity < 1) {
      res.status(400).json({ error: 'productId and quantity (>=1) are required' });
      return;
    }

    const queueName = process.env.MQ_REQUEST_QUEUE || 'ORDER.REQ';
    const payload = JSON.stringify({
      orderId: correlationId,
      productId,
      quantity,
      submittedAt: new Date().toISOString(),
    });

    await tracer.startActiveSpan('inventory.check', async (checkSpan) => {
      checkSpan.setAttribute('inventory.product_id', productId);
      checkSpan.setAttribute('order.quantity', quantity);
      try {
        const checkRes = await fetch(`${inventoryUrl}/check`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Correlation-Id': correlationId,
          },
          body: JSON.stringify({ productId, quantity }),
        });
        if (!checkRes.ok) {
          const detail = await checkRes.text();
          checkSpan.setStatus({ code: SpanStatusCode.ERROR, message: `inventory check ${checkRes.status}` });
          res.status(checkRes.status === 409 ? 409 : 503).json({
            error: checkRes.status === 409 ? 'Insufficient inventory' : 'Inventory service unavailable',
            detail: detail.slice(0, 200),
          });
          return;
        }

        await tracer.startActiveSpan('mq.put.order', async (span) => {
          span.setAttribute('messaging.system', 'ibmmq');
          span.setAttribute('messaging.destination.name', queueName);
          span.setAttribute('order.product_id', productId);
          span.setAttribute('order.quantity', quantity);

          const config = loadMqConfig();
          let hConn: Awaited<ReturnType<typeof connect>> | undefined;
          try {
            hConn = await connect(config);
            const hQueue = await openQueue(hConn, queueName, MQC.MQOO_OUTPUT | MQC.MQOO_FAIL_IF_QUIESCING);
            const { msgId } = await putMessage(hQueue, Buffer.from(payload, 'utf8'), correlationId);
            span.setAttribute('messaging.message_id', msgId.toString('hex'));

            log.info('Order message published to IBM MQ', {
              correlationId,
              queue: queueName,
              msgId: msgId.toString('hex'),
              productId,
              quantity,
            });

            res.status(202).json({
              status: 'accepted',
              queue: queueName,
              orderId: correlationId,
              msgId: msgId.toString('hex'),
            });
          } catch (err) {
            const error = err as Error;
            span.recordException(error);
            span.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
            log.error('Failed to publish order to IBM MQ', {
              correlationId,
              queue: queueName,
              error: { message: error.message, stack: error.stack, type: error.name },
            });
            res.status(503).json({ error: 'Message broker unavailable', detail: error.message });
          } finally {
            if (hConn) {
              await disconnect(hConn).catch(() => undefined);
            }
            span.end();
          }
        });
      } catch (err) {
        const error = err as Error;
        checkSpan.recordException(error);
        checkSpan.setStatus({ code: SpanStatusCode.ERROR, message: error.message });
        res.status(503).json({ error: 'Inventory service unavailable', detail: error.message });
      } finally {
        checkSpan.end();
      }
    });
  })
);

useServiceErrorHandler(app, SERVICE_NAME);

const port = Number(process.env.PORT || 8080);
app.listen(port, () => {
  log.info('Order producer listening', { port });
});
