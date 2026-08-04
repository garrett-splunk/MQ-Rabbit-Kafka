import type { Request, Response, NextFunction } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { createLogger } from './logger.js';

export function getCorrelationId(req: Request): string {
  return (req.headers['x-correlation-id'] as string) || 'unknown';
}

export function correlationMiddleware(req: Request, res: Response, next: NextFunction): void {
  const incoming = req.headers['x-correlation-id'] as string | undefined;
  const correlationId = incoming || uuidv4();
  req.headers['x-correlation-id'] = correlationId;
  res.setHeader('X-Correlation-Id', correlationId);
  next();
}

export function requestLoggingMiddleware(serviceName: string) {
  const log = createLogger(serviceName);
  return (req: Request, res: Response, next: NextFunction): void => {
    const start = Date.now();
    const correlationId = getCorrelationId(req);

    res.on('finish', () => {
      const durationMs = Date.now() - start;
      const level = res.statusCode >= 500 ? 'error' : res.statusCode >= 400 ? 'warn' : 'info';
      log[level](`${req.method} ${req.originalUrl} ${res.statusCode}`, {
        correlationId,
        httpMethod: req.method,
        httpRoute: req.route?.path || req.path,
        httpStatus: res.statusCode,
        durationMs,
      });
    });

    next();
  };
}

export function asyncHandler(
  fn: (req: Request, res: Response, next: NextFunction) => Promise<void>
) {
  return (req: Request, res: Response, next: NextFunction): void => {
    fn(req, res, next).catch(next);
  };
}

export function createErrorHandler(serviceName: string) {
  const log = createLogger(serviceName);
  return (err: Error, req: Request, res: Response, _next: NextFunction): void => {
    const correlationId = getCorrelationId(req);
    const status = (err as Error & { status?: number }).status ?? 500;

    log.error(err.message, {
      correlationId,
      httpMethod: req.method,
      httpRoute: req.path,
      httpStatus: status,
      error: {
        message: err.message,
        stack: err.stack,
        type: err.name,
      },
    });

    res.status(status).json({
      error: err.message || 'Internal server error',
    });
  };
}

export { createLogger };
