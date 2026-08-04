const baseUrl = process.env.PRODUCER_URL || 'http://localhost:8080';
const count = Number(process.argv[2] || 20);
const delayMs = Number(process.argv[3] || 500);

async function sleep(ms: number): Promise<void> {
  await new Promise((r) => setTimeout(r, ms));
}

async function main(): Promise<void> {
  console.log(`Sending ${count} orders to ${baseUrl} (${delayMs}ms apart)`);
  for (let i = 0; i < count; i += 1) {
    const correlationId = `load-${Date.now()}-${i}`;
    const res = await fetch(`${baseUrl}/orders`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Correlation-Id': correlationId,
      },
      body: JSON.stringify({ productId: `SKU-${100 + (i % 5)}`, quantity: 1 + (i % 3) }),
    });
    const body = await res.text();
    console.log(res.status, correlationId, body.slice(0, 120));
    if (delayMs > 0) await sleep(delayMs);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
