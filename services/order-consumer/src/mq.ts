import mq from 'ibmmq';

const MQC = mq.MQC;

export interface MqConfig {
  queueManager: string;
  connName: string;
  channel: string;
  user: string;
  password: string;
}

export function loadMqConfig(): MqConfig {
  return {
    queueManager: process.env.MQ_QUEUE_MANAGER || 'QM1',
    connName: process.env.MQ_CONN_NAME || 'mq(1414)',
    channel: process.env.MQ_CHANNEL || 'DEV.APP.SVRCONN',
    user: process.env.MQ_USER || 'app',
    password: process.env.MQ_APP_PASSWORD || 'passw0rd',
  };
}

export function connect(config: MqConfig): Promise<mq.MQObject> {
  return new Promise((resolve, reject) => {
    const connectionOptions = new mq.MQCNO();
    connectionOptions.Options = MQC.MQCNO_CLIENT_BINDING;

    const clientConn = new mq.MQCD();
    clientConn.ConnectionName = config.connName;
    clientConn.ChannelName = config.channel;
    connectionOptions.ClientConn = clientConn;

    const security = new mq.MQCSP();
    security.UserId = config.user;
    security.Password = config.password;
    connectionOptions.SecurityParms = security;

    mq.Connx(config.queueManager, connectionOptions, (err, hConn) => {
      if (err) {
        reject(err);
        return;
      }
      resolve(hConn);
    });
  });
}

export function openQueue(hConn: mq.MQObject, queueName: string, openOptions: number): Promise<mq.MQObject> {
  return new Promise((resolve, reject) => {
    const od = new mq.MQOD();
    od.ObjectName = queueName;
    od.ObjectType = MQC.MQOT_Q;
    mq.Open(hConn, od, openOptions, (err, hObj) => {
      if (err) reject(err);
      else resolve(hObj);
    });
  });
}

export function putMessage(
  hObj: mq.MQObject,
  body: Buffer,
  correlationId?: string
): Promise<{ msgId: Buffer }> {
  return new Promise((resolve, reject) => {
    const md = new mq.MQMD();
    if (correlationId) {
      md.CorrelId = Buffer.from(correlationId.padEnd(24, ' ').slice(0, 24));
    }
    md.Format = MQC.MQFMT_STRING;
    const pmo = new mq.MQPMO();
    mq.Put(hObj, md, pmo, body, (err: mq.MQError | null) => {
      if (err) reject(err);
      else resolve({ msgId: md.MsgId });
    });
  });
}

function extractMessageBody(buf: Buffer, len: number): string {
  const raw = buf.toString('utf8', 0, len);
  const jsonStart = raw.indexOf('{');
  return jsonStart >= 0 ? raw.slice(jsonStart) : raw;
}

export function getMessage(hObj: mq.MQObject, waitIntervalMs = 5000): Promise<{ body: string; msgId: string; correlId: string }> {
  // ibmmq async Get() callbacks can hang under linux/amd64 emulation (Docker Desktop on Apple Silicon).
  // GetSync is reliable for this lab; run off the main tick so health checks stay responsive.
  return new Promise((resolve, reject) => {
    setImmediate(() => {
      const md = new mq.MQMD();
      const gmo = new mq.MQGMO();
      gmo.Options = MQC.MQGMO_WAIT | MQC.MQGMO_CONVERT;
      gmo.WaitInterval = waitIntervalMs;
      const buf = Buffer.alloc(1024 * 64);

      try {
        const len = mq.GetSync(hObj, md, gmo, buf) ?? 0;
        resolve({
          body: extractMessageBody(buf, len),
          msgId: bufToHex(md.MsgId),
          correlId: bufToHex(md.CorrelId),
        });
      } catch (err) {
        reject(err);
      }
    });
  });
}

function bufToHex(buf: Buffer | undefined): string {
  if (!buf) return '';
  return buf.toString('hex');
}

export function disconnect(hConn: mq.MQObject): Promise<void> {
  return new Promise((resolve, reject) => {
    mq.Disc(hConn, (err) => {
      if (err) reject(err);
      else resolve();
    });
  });
}

export { MQC };
