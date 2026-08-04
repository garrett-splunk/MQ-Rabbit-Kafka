import { initObservability } from './otel.js';

const serviceName = process.env.OTEL_SERVICE_NAME;
if (serviceName) {
  initObservability({ serviceName });
}
