const { context } = require('@opentelemetry/api');
const { logs, SeverityNumber } = require('@opentelemetry/api-logs');
const { OTLPLogExporter } = require('@opentelemetry/exporter-logs-otlp-proto');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-proto');
const { LoggerProvider, SimpleLogRecordProcessor } = require('@opentelemetry/sdk-logs');
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');

const enabled = Boolean(process.env.OTEL_EXPORTER_OTLP_ENDPOINT);
const loggerProvider = enabled ? new LoggerProvider({
  processors: [new SimpleLogRecordProcessor(new OTLPLogExporter())],
}) : undefined;
if (enabled) {
  logs.setGlobalLoggerProvider(loggerProvider);
}

const sdk = new NodeSDK({
  instrumentations: [getNodeAutoInstrumentations()],
  metricReader: enabled ? new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter(),
    exportIntervalMillis: Number(process.env.OTEL_METRIC_EXPORT_INTERVAL || 10000),
  }) : undefined,
});
sdk.start();

const originalConsole = { log: console.log, error: console.error, warn: console.warn };
const severity = { log: SeverityNumber.INFO, warn: SeverityNumber.WARN, error: SeverityNumber.ERROR };
for (const method of Object.keys(originalConsole)) {
  console[method] = (...args) => {
    originalConsole[method](...args);
    if (!enabled) return;
    const body = args.length === 1 ? args[0] : args.map(String).join(' ');
    const record = logs.getLogger('console').emit({
      body,
      severityNumber: severity[method],
      severityText: method.toUpperCase(),
      attributes: { 'log.type': 'console' },
      context: context.active(),
      timestamp: Date.now(),
    });
    return record;
  };
}

process.once('SIGTERM', async () => {
  const tasks = [sdk.shutdown()];
  if (loggerProvider) tasks.push(loggerProvider.shutdown());
  await Promise.all(tasks);
});