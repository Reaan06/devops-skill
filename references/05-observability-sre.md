# Observability & Site Reliability Engineering (SRE)

## 1. Executive Overview

Observability in cloud-native production architectures connects telemetry data across three core domains: **distributed traces**, **time-series metrics**, and **structured logs**.

Modern SRE standards (2025/2026) enforce:

1. **Vendor-Neutral Telemetry**: Standardizing exclusively on the **OpenTelemetry (OTel)** framework (OTel Collector, OTLP protocol over gRPC/HTTP).
2. **Context Propagation via W3C Standards**: Unbroken end-to-end trace context injection using the `traceparent` header across HTTP, gRPC, and messaging queues (Kafka, RabbitMQ).
3. **Trace-Log Correlation**: Emitting structured single-line JSON logs that automatically inject `trace_id` and `span_id` matching active spans.
4. **The 4 Golden Signals**: Implementing automated Prometheus alerts on **Latency**, **Traffic**, **Errors**, and **Saturation** paired with Multi-Window Multi-Burn-Rate alerting for Service Level Objectives (SLOs).

---

## 2. OpenTelemetry Collector Architecture

The OpenTelemetry Collector acts as an out-of-process telemetry proxy and transformation pipeline. Instead of applications maintaining direct SDK connections to backend storage platforms (Prometheus, Jaeger, Tempo, Loki, Datadog), applications emit data locally over OTLP (`localhost:4317` gRPC or `localhost:4318` HTTP).

### 2.1 Deployment Topologies

```text
[ Pod A ] ──OTLP──┐
                  ▼
[ Pod B ] ──OTLP──> [ OTel Collector DaemonSet / Sidecar ]
                          │ (Process, batch, sanitize PII, memory limit)
                          ▼
                    [ OTel Collector Gateway Deployment ]
                          │
       ┌──────────────────┼──────────────────┐
       ▼                  ▼                  ▼
 [ Traces: Tempo ]  [ Metrics: Prometheus ] [ Logs: Loki/S3 ]
```

- **DaemonSet / Node Agent**: Collects host metrics, kubelet metrics, and acts as a local OTLP receiver for all pods on the node.
- **Gateway Deployment**: Scalable cluster of collectors managing sampling decisions (tail-based sampling), tenant routing, rate-limiting, and credentials for cloud storage backends.

---

## 3. The 4 Golden Signals with Prometheus

Defined in the Google SRE Handbook, the 4 Golden Signals measure user-facing health and underlying infrastructure limits.

### 3.1 Prometheus PromQL Rules

#### 1. Latency (Duration of requests, separating successful requests from errors)

P99 HTTP Request Duration over a 5-minute sliding window:

```promql
histogram_quantile(
  0.99,
  sum(rate(http_request_duration_seconds_bucket{job="backend-api"}[5m])) by (le, path)
)
```

#### 2. Traffic (Measure of demand placed on the system)

Total incoming requests per second:

```promql
sum(rate(http_requests_total{job="backend-api"}[1m])) by (status_code)
```

#### 3. Errors (Rate of requests that fail explicitly or implicitly)

Error ratio percentage (5xx HTTP responses relative to total traffic):

```promql
(
  sum(rate(http_requests_total{job="backend-api", status_code=~"5.."}[5m]))
  /
  sum(rate(http_requests_total{job="backend-api"}[5m]))
) * 100
```

#### 4. Saturation (How "full" the service is, measuring constrained resources)

Memory saturation relative to container limits:

```promql
(
  container_memory_working_set_bytes{container="backend-api"}
  /
  container_spec_memory_limit_bytes{container="backend-api"}
) * 100 > 85
```

---

## 4. Structured JSON Logging & W3C Traceparent Injection

Plain-text string logs formatted arbitrarily (e.g. `[INFO] User logged in: 123`) defeat automated parsing, aggregation, and querying at scale.

### 4.1 Production Structured Log Schema

Every log statement MUST be emitted as a single-line JSON string to standard output (`stdout`), containing standard semantic keys:

```json
{
  "timestamp": "2026-03-30T14:32:01.124Z",
  "level": "INFO",
  "service": "order-service",
  "version": "1.4.2",
  "environment": "production",
  "message": "Processed payment transaction successfully",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "00f067aa0ba902b7",
  "trace_flags": "01",
  "http": {
    "method": "POST",
    "route": "/api/v1/orders/checkout",
    "status_code": 200,
    "duration_ms": 42.15
  },
  "user_id": "usr_998124"
}
```

### 4.2 W3C Traceparent Header Specification

When an upstream service (or edge reverse proxy) forwards an HTTP request, it injects the W3C `traceparent` header:

```text
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
              │  └──────────────┬───────────────┘ └───────┬────────┘ └─┬┘
           version          trace_id                   parent_id     flags
```

- **Version** (`00`): W3C specification version.
- **Trace ID** (`32 hex characters`): 16-byte array unique to the entire distributed transaction.
- **Span ID / Parent ID** (`16 hex characters`): 8-byte array unique to the calling span.
- **Trace Flags** (`01`): Bitmask flag (`01` indicates the trace was recorded/sampled).

### 4.3 Why Trace-Log Correlation Matters in Incident Response

When an alert fires in Grafana or PagerDuty:

1. The on-call engineer inspects the failing HTTP 500 error in Loki or Elasticsearch.
2. Clicking the embedded `trace_id` hyperlinks immediately into Tempo or Jaeger.
3. The engineer inspects the exact flame graph, identifying which downstream database query or microservice RPC timed out or threw an exception, reducing Mean Time to Resolution (MTTR) from hours to minutes.

---

## 5. Multi-Window Multi-Burn-Rate Alerting

Legacy alerts firing on single threshold spikes (e.g. "Error rate > 1% for 5 minutes") cause alert fatigue. Modern SRE uses **Multi-Window Multi-Burn-Rate** alerting against Service Level Objectives (SLOs).

For a 99.9% availability SLO over a 30-day window (Error Budget = 0.1%):

| Severity | Burn Rate | Budget Consumed | Time to Exhaustion | Short Window | Long Window | Notification Channel |
| --- | --- | --- | --- | --- | --- | --- |
| **Page** | 14.4x | 2% | 1 hour | 2 minutes | 1 hour | PagerDuty / On-Call Voice |
| **Page** | 6x | 5% | 6 hours | 5 minutes | 6 hours | PagerDuty |
| **Ticket** | 1x | 10% | 3 days | 30 minutes | 3 days | Jira / Slack Channel |

By requiring both a short window and a long window to be burning simultaneously, the alert guarantees that the incident is both severe and actively continuing, eliminating transient false-positive pages.
