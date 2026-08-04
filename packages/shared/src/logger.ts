import { context, trace } from '@opentelemetry/api';

export type LogSeverity = 'DEBUG' | 'INFO' | 'WARN' | 'ERROR' | 'FATAL';

export interface LogContext {
  correlationId?: string;
  traceId?: string;
  spanId?: string;
  httpMethod?: string;
  httpRoute?: string;
  httpStatus?: number;
  durationMs?: number;
  queue?: string;
  msgId?: string;
  correlationIdMq?: string;
  error?: string | { message: string; stack?: string; type?: string };
  [key: string]: unknown;
}

export interface StructuredLogger {
  debug(message: string, meta?: LogContext): void;
  info(message: string, meta?: LogContext): void;
  warn(message: string, meta?: LogContext): void;
  error(message: string, meta?: LogContext): void;
  fatal(message: string, meta?: LogContext): void;
}

const DEPLOYMENT_ENV = process.env.DEPLOYMENT_ENVIRONMENT || process.env.NODE_ENV || 'messaging-demo-lab';

const SEVERITY_MAP: Record<LogSeverity, string> = {
  DEBUG: 'DEBUG',
  INFO: 'INFO',
  WARN: 'WARN',
  ERROR: 'ERROR',
  FATAL: 'FATAL',
};

function getTraceContext(): { traceId?: string; spanId?: string } {
  const span = trace.getSpan(context.active());
  if (!span) return {};
  const spanContext = span.spanContext();
  if (!spanContext.traceId) return {};
  return { traceId: spanContext.traceId, spanId: spanContext.spanId };
}

function severityToNumber(severity: LogSeverity): number {
  switch (severity) {
    case 'DEBUG':
      return 5;
    case 'INFO':
      return 9;
    case 'WARN':
      return 13;
    case 'ERROR':
      return 17;
    case 'FATAL':
      return 21;
  }
}

function stripKnownFields(meta: LogContext): Record<string, unknown> {
  const {
    correlationId: _c,
    traceId: _t,
    spanId: _s,
    httpMethod: _hm,
    httpRoute: _hr,
    httpStatus: _hs,
    durationMs: _d,
    queue: _q,
    msgId: _m,
    correlationIdMq: _cm,
    error: _e,
    ...rest
  } = meta;
  return Object.keys(rest).length ? rest : {};
}

function emit(severity: LogSeverity, serviceName: string, message: string, meta: LogContext = {}): void {
  const traceCtx = getTraceContext();
  const payload = {
    timestamp: new Date().toISOString(),
    severityText: SEVERITY_MAP[severity],
    severityNumber: severityToNumber(severity),
    body: message,
    'service.name': serviceName,
    'deployment.environment': DEPLOYMENT_ENV,
    'deployment.environment.name': DEPLOYMENT_ENV,
    correlation_id: meta.correlationId,
    trace_id: meta.traceId || traceCtx.traceId,
    span_id: meta.spanId || traceCtx.spanId,
    http_method: meta.httpMethod,
    http_route: meta.httpRoute,
    http_status: meta.httpStatus,
    duration_ms: meta.durationMs,
    mq_queue: meta.queue,
    mq_msg_id: meta.msgId,
    mq_correlation_id: meta.correlationIdMq,
    ...(meta.error
      ? {
          error: typeof meta.error === 'string' ? { message: meta.error } : meta.error,
        }
      : {}),
    attributes: stripKnownFields(meta),
  };

  const line = JSON.stringify(payload);
  if (severity === 'ERROR' || severity === 'FATAL') {
    console.error(line);
  } else if (severity === 'WARN') {
    console.warn(line);
  } else {
    console.log(line);
  }
}

export function createLogger(serviceName: string): StructuredLogger {
  return {
    debug: (message, meta) => emit('DEBUG', serviceName, message, meta),
    info: (message, meta) => emit('INFO', serviceName, message, meta),
    warn: (message, meta) => emit('WARN', serviceName, message, meta),
    error: (message, meta) => emit('ERROR', serviceName, message, meta),
    fatal: (message, meta) => emit('FATAL', serviceName, message, meta),
  };
}
