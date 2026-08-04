import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-http';
import { PeriodicExportingMetricReader } from '@opentelemetry/sdk-metrics';
import { Resource } from '@opentelemetry/resources';
import {
  ATTR_SERVICE_NAME,
  ATTR_DEPLOYMENT_ENVIRONMENT_NAME,
} from '@opentelemetry/semantic-conventions';

let sdk: NodeSDK | null = null;

export interface ObservabilityOptions {
  serviceName: string;
  deploymentEnvironment?: string;
}

function buildResource(serviceName: string, deploymentEnvironment: string): Resource {
  return new Resource({
    [ATTR_SERVICE_NAME]: serviceName,
    [ATTR_DEPLOYMENT_ENVIRONMENT_NAME]: deploymentEnvironment,
    'deployment.environment': deploymentEnvironment,
    'service.namespace': 'mq-rabbit-kafka-demo',
    'demo.name': 'mq-rabbit-kafka-demo',
  });
}

export function initObservability(options: ObservabilityOptions): void {
  if (process.env.OTEL_SDK_DISABLED === 'true') return;
  if (sdk) return;

  const serviceName = options.serviceName;
  const deploymentEnvironment =
    options.deploymentEnvironment ||
    process.env.DEPLOYMENT_ENVIRONMENT ||
    process.env.NODE_ENV ||
    'messaging-demo-lab';

  process.env.OTEL_SERVICE_NAME = serviceName;

  const otlpEndpoint =
    process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://otel-collector:4318';

  const resource = buildResource(serviceName, deploymentEnvironment);

  sdk = new NodeSDK({
    resource,
    traceExporter: new OTLPTraceExporter({
      url: `${otlpEndpoint}/v1/traces`,
    }),
    metricReader: new PeriodicExportingMetricReader({
      exporter: new OTLPMetricExporter({
        url: `${otlpEndpoint}/v1/metrics`,
      }),
      exportIntervalMillis: 15000,
    }),
    instrumentations: [
      getNodeAutoInstrumentations({
        '@opentelemetry/instrumentation-fs': { enabled: false },
        '@opentelemetry/instrumentation-dns': { enabled: false },
        '@opentelemetry/instrumentation-http': {
          ignoreIncomingRequestHook: (req) => (req.url ?? '').includes('/health'),
        },
      }),
    ],
  });

  sdk.start();

  process.on('SIGTERM', () => {
    sdk?.shutdown().catch(() => undefined);
  });
}
