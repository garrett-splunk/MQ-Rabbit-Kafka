import express from 'express';
import { trace, SpanStatusCode } from '@opentelemetry/api';
import {
  bootstrapService,
  useServiceErrorHandler,
  asyncHandler,
  getCorrelationId,
  createLogger,
} from '@mq-lab/shared';

const SERVICE_NAME = 'inventory-service';
const log = createLogger(SERVICE_NAME);
const tracer = trace.getTracer(SERVICE_NAME);

const stock = new Map<string, number>([
  ['SKU-100', 500],
  ['SKU-101', 500],
  ['SKU-102', 500],
  ['SKU-103', 500],
  ['SKU-104', 500],
  ['SKU-JAVA', 500],
  ['SKU-APM', 500],
]);

function getOnHand(productId: string): number {
  if (!stock.has(productId)) {
    stock.set(productId, 250);
  }
  return stock.get(productId)!;
}

const app = express();
app.use(express.json());
bootstrapService({ app, serviceName: SERVICE_NAME });

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: SERVICE_NAME, skus: stock.size });
});

app.post(
  '/check',
  asyncHandler(async (req, res) => {
    const correlationId = getCorrelationId(req);
    const { productId, quantity } = req.body as { productId?: string; quantity?: number };

    if (!productId || typeof quantity !== 'number' || quantity < 1) {
      res.status(400).json({ error: 'productId and quantity (>=1) are required' });
      return;
    }

    await tracer.startActiveSpan('inventory.reserve.check', async (span) => {
      span.setAttribute('inventory.product_id', productId);
      span.setAttribute('order.quantity', quantity);
      try {
        const onHand = getOnHand(productId);
        const available = onHand >= quantity;
        span.setAttribute('inventory.on_hand', onHand);
        span.setAttribute('inventory.available', available);

        log.info('Inventory check', { correlationId, productId, quantity, onHand, available });

        if (!available) {
          span.setStatus({ code: SpanStatusCode.ERROR, message: 'insufficient stock' });
          res.status(409).json({ available: false, productId, onHand, quantity });
          return;
        }

        res.json({ available: true, productId, onHand, quantity });
      } finally {
        span.end();
      }
    });
  })
);

app.post(
  '/fulfill',
  asyncHandler(async (req, res) => {
    const correlationId = getCorrelationId(req);
    const { orderId, productId, quantity } = req.body as {
      orderId?: string;
      productId?: string;
      quantity?: number;
    };

    if (!orderId || !productId || typeof quantity !== 'number' || quantity < 1) {
      res.status(400).json({ error: 'orderId, productId, and quantity (>=1) are required' });
      return;
    }

    await tracer.startActiveSpan('inventory.fulfill', async (span) => {
      span.setAttribute('order.id', orderId);
      span.setAttribute('inventory.product_id', productId);
      span.setAttribute('order.quantity', quantity);
      try {
        const onHand = getOnHand(productId);
        const nextOnHand = Math.max(0, onHand - quantity);
        stock.set(productId, nextOnHand);
        span.setAttribute('inventory.on_hand_after', nextOnHand);

        log.info('Inventory fulfilled', {
          correlationId,
          orderId,
          productId,
          quantity,
          onHandAfter: nextOnHand,
        });

        res.json({ fulfilled: true, orderId, productId, onHand: nextOnHand });
      } finally {
        span.end();
      }
    });
  })
);

useServiceErrorHandler(app, SERVICE_NAME);

const port = Number(process.env.PORT || 8082);
app.listen(port, () => {
  log.info('Inventory service listening', { port });
});
