# SRE, Observabilidad, FinOps e Ingeniería Especializada X-Ops

## 1. Explicación: Conceptos y Arquitectura

La resiliencia moderna de plataformas une la observabilidad operacional, la gobernanza financiera, los objetivos matemáticos de nivel de servicio y disciplinas operativas altamente especializadas en una arquitectura unificada de retroalimentación. Cuando los sistemas escalan a miles de microservicios y topologías multi-cloud, el trabajo manual no planificado (*toil*) debe ser reemplazado por **pipelines de telemetría agnósticos del proveedor**, **alertas de tasa de consumo multi-ventana (MWMBR)**, **asignación automatizada de costes** y **automatización por dominios X-Ops**.

```text
 ┌────────────────────────────────────────────────────────────────────────┐
 │                      Cargas de Trabajo y Cómputo Kubernetes            │
 │  • Las aplicaciones emiten trazas OTLP, métricas y logs JSON monolínea │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │ OTLP (gRPC: 4317 / HTTP: 4318)
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ Pipeline de OpenTelemetry Collector                                    │
 │  • Receptores: OTLP, Prometheus, Host Metrics                          │
 │  • Procesadores: memory_limiter, batch, k8sattributes, transform (PII) │
 │  • Exportadores: Prometheus (Métricas), Tempo (Trazas), Loki (Logs)    │
 └─────────────────┬──────────────────────────────────┬───────────────────┘
                   │                                  │
                   ▼                                  ▼
 ┌──────────────────────────────────┐ ┌───────────────────────────────────┐
 │ Motor de Confiabilidad SRE       │ │ Motor de Inteligencia FinOps      │
 │  • 4 Señales Doradas             │ │  • Asignación de costes OpenCost  │
 │  • Alertas Multi-Burn-Rate       │ │  • Dimensionamiento con PromQL    │
 │  • Congelación por Error Budget  │ │  • Bin-packing Spot con Karpenter │
 │  • Validación de Caos con Mesh   │ │  • Showback por centros de coste  │
 └──────────────────────────────────┘ └───────────────────────────────────┘
                   ▲                                  ▲
                   │                                  │
 ┌─────────────────┴──────────────────────────────────┴───────────────────┐
 │ Dominios Especializados de Ejecución X-Ops                             │
 │  • MLOps / LLMOps: vLLM PagedAttention, GPU slicing (MIG), caché DVC   │
 │  • DataOps: dbt Slim CI (state:modified+), compuertas Great Expectation│
 │  • NetOps: NetBox SSoT, emulación CI con Containerlab, gNMI            │
 │  • NoOps: Escalado a cero Knative, CloudEvents, Outbox transaccional   │
 └────────────────────────────────────────────────────────────────────────┘
```

### 1.1 La Trinidad de Observabilidad en SRE y OpenTelemetry Collector

La observabilidad conecta el estado distribuido de las aplicaciones a través de tres dimensiones complementarias:

1. **Trazado Distribuido (Distributed Tracing)**: Registra la ruta exacta de una petición a través del grafo de microservicios. Las trazas propagan el estándar **W3C TraceContext** (`traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01`) en cabeceras HTTP, metadatos gRPC y colas de mensajería (Kafka, RabbitMQ).
2. **Métricas de Series Temporales**: Cuantifican el rendimiento y saturación en tiempo real (consumo de CPU, memoria, tasa de peticiones y percentiles de latencia).
3. **Logs Estructurados**: Eventos JSON de una sola línea que incluyen timestamp, nivel de severidad, mensaje y los identificadores correlacionados `trace_id` y `span_id`.

El **OpenTelemetry Collector** opera como un proxy desacoplado de telemetría. En lugar de acoplar las aplicaciones a SDKs propietarios de proveedores (Datadog, New Relic, Splunk), los contenedores emiten telemetría mediante el protocolo estándar OTLP. El colector gestiona el almacenamiento intermedio en memoria (*buffering*), procesamiento por lotes (*batching*), ofuscación de datos personales (PII), muestreo en la cola (*tail-based sampling*) y distribución multitienda (*fan-out*).

### 1.2 SRE Matemático: SLIs, SLOs y Alertas Multi-Window Multi-Burn-Rate

La disciplina de Site Reliability Engineering modela matemáticamente la disponibilidad del servicio:

$$\text{SLI} = \frac{\sum \text{Peticiones Correctas}}{\sum \text{Total de Peticiones Válidas}} \times 100\%$$

$$\text{Error Budget} = 100\% - \text{SLO}$$

#### Por Qué Fallan las Alertas Tradicionales

- **Alertas de Umbral Único** (por ejemplo: alertar si el error supera el $1\%$ durante 5 minutos): Generan excesivas alertas falsas ante fluctuaciones transitorias que se corrigen solas.
- **Alertas de Ventana Amplia** (por ejemplo: alertar si el error supera el $0.1\%$ a lo largo de 24 horas): Detectan anomalías reales demasiado tarde, cuando el presupuesto de error (*error budget*) ya ha sido completamente consumido.

#### Alertas Multi-Ventana y Multi-Tasa de Consumo (MWMBR)

El estándar de SRE de Google supera este problema evaluando en paralelo una ventana temporal corta (para confirmar que el incidente está activo) y una ventana larga (para asegurar significancia estadística) sobre distintas velocidades de consumo:

| Tasa de Consumo (Burn Rate) | % Presupuesto Agotado | Tiempo para Consumo Total | Ventana Corta | Ventana Larga | Severidad de Alerta | Respuesta Operativa |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **14.4x** | 2% | 2 días | 2 minutos | 1 hora | Crítica / Page | Notificación inmediata a guardia; incidente grave en curso. |
| **6.0x** | 5% | 5 días | 6 minutos | 6 horas | Crítica / Page | Degradación severa consumiendo cuota rápidamente. |
| **1.0x** | 10% | 30 días | 30 minutos | 3 días | Advertencia / Ticket | Ticket de baja prioridad; investigar en horario laboral. |

### 1.3 Ingeniería del Caos Guiada por Hipótesis

La confiabilidad no se demuestra mediante monitorización pasiva. La **Ingeniería del Caos** introduce deliberadamente fallos controlados en infraestructura y redes para verificar la resiliencia del sistema:
- **Latencia y Jitter de Red**: Comprobar que los servicios clientes aplican timeouts estrictos y disyuntores (*circuit breakers*) sin saturar los pools de hilos.
- **Pérdida de Paquetes y Particionamiento**: Validar algoritmos de consenso y protocolos de elección en bases de datos distribuidas (Raft, Paxos).
- **Desalojo Forzado de Nodos y Pods**: Garantizar que los servicios en Kubernetes preserven la disponibilidad mediante PodDisruptionBudgets y reglas de anti-afinidad.

### 1.4 FinOps Cloud-Native y Autoescalado Dinámico con Karpenter

El aprovisionamiento estático tradicional genera una baja utilización media del clúster ($< 15\%$), provocando un gasto desmedido en infraestructura cloud. El ciclo de vida de FinOps se articula en tres etapas: **Informar -> Optimizar -> Operar**:
- **Informar**: Asignación de costes en tiempo real que mapea la facturación cloud hacia namespaces, etiquetas y equipos mediante **OpenCost**.
- **Optimizar**: Identificación proactiva de holguras (*slack*) de CPU y memoria a partir de métricas reales de telemetría.
- **Operar**: Orquestación dinámica del cómputo con **Karpenter**:
  - Aprovisiona instancias optimizadas consultando directamente las APIs del proveedor cloud según los requisitos de los pods pendientes, omitiendo los Auto Scaling Groups tradicionales.
  - Diversifica familias de instancias en grupos de capacidad Spot para absorber interrupciones de capacidad sin degradar el servicio.
  - Ejecuta **consolidación continua**, drenando nodos infrautilizados y migrando pods a instancias más económicas y ajustadas a la carga real.

### 1.5 Disciplinas Especializadas de X-Ops

La ingeniería moderna de plataformas expande las prácticas de DevOps a dominios avanzados:

1. **MLOps / LLMOps**: Gestiona el grafo de dependencias entre código fuente, datos de entrenamiento y pesos de modelos.
   - **Inferencia vLLM**: Emplea PagedAttention para eliminar la fragmentación de memoria del KV-cache y procesamiento continuo por lotes (*continuous batching*) para inferencia de alto rendimiento.
   - **Virtualización de GPU**: Particionamiento Multi-Instance GPU (MIG) para segmentar aceleradores NVIDIA H100/A100 entre múltiples procesos de inferencia.
   - **Trazabilidad de Datos**: Data Version Control (DVC) para versionar hashes de datasets de gran volumen vinculados a commits de Git.
2. **DataOps**: Aplica entrega continua y control estadístico de calidad sobre pipelines analíticos.
   - **dbt Slim CI**: Compara el estado de la rama contra los manifiestos de producción, ejecutando transformaciones únicamente sobre modelos modificados (`dbt build --select state:modified+`).
   - **Validación de Calidad**: Compuertas automáticas con Great Expectations en la frontera de ingesta analítica.
3. **NetOps (Network as Code)**: Reemplaza la configuración manual de switches por automatización declarativa.
   - **Fuente Única de Verdad (SSoT)**: NetBox o Nautobot modelando IPAM, VLANs y enlaces BGP.
   - **Emulación de Red en CI**: Containerlab ejecutando sistemas operativos de red virtualizados (Arista cEOS, Nokia SR Linux) en GitHub Actions para validar topologías de enrutamiento previo al despliegue físico.
4. **NoOps y Serverless**: Abstrae por completo la gestión del ciclo de vida de servidores mediante computación reactiva guiada por eventos.
   - **Knative Serving**: Escala contenedores sin estado a cero réplicas en inactividad y escala elásticamente a cientos de réplicas al recibir tráfico HTTP.
   - **CloudEvents**: Estandariza la envoltura de eventos asíncronos (`type`, `source`, `id`, `data`) entre microservicios distribuidos.
   - **Patrón Outbox Transaccional y Sagas**: Coordina operaciones distribuidas multi-servicio evitando bloqueos rígidos de two-phase commit.

---

## 2. Guías Prácticas: Blueprints y Configuraciones de Producción

### 2.1 Configuración de Pipeline en OpenTelemetry Collector (`otel-collector-config.yaml`)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-collector-config
  namespace: monitoring
data:
  config.yaml: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      prometheus:
        config:
          scrape_configs:
            - job_name: 'otel-collector'
              scrape_interval: 15s
              static_configs:
                - targets: ['0.0.0.0:8888']

    processors:
      memory_limiter:
        check_interval: 1s
        limit_percentage: 75
        spike_limit_percentage: 20
      batch:
        send_batch_size: 8192
        timeout: 200ms
      k8sattributes:
        auth_type: "serviceAccount"
        passthrough: false
        extract:
          metadata:
            - k8s.pod.name
            - k8s.pod.uid
            - k8s.deployment.name
            - k8s.namespace.name
            - k8s.node.name

    exporters:
      prometheus:
        endpoint: "0.0.0.0:8889"
      otlp/tempo:
        endpoint: "tempo.monitoring.svc.cluster.local:4317"
        tls:
          insecure: true
      otlphttp/loki:
        endpoint: "http://loki.monitoring.svc.cluster.local:3100/otlp"

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, k8sattributes, batch]
          exporters: [otlp/tempo]
        metrics:
          receivers: [otlp, prometheus]
          processors: [memory_limiter, k8sattributes, batch]
          exporters: [prometheus]
        logs:
          receivers: [otlp]
          processors: [memory_limiter, k8sattributes, batch]
          exporters: [otlphttp/loki]
```

### 2.2 Esquema de Logs Estructurados JSON Monolínea (`structured-log-spec.json`)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "ProductionStructuredLogEvent",
  "type": "object",
  "required": ["timestamp", "severity", "message", "service", "trace_id", "span_id"],
  "properties": {
    "timestamp": { "type": "string", "format": "date-time" },
    "severity": { "type": "string", "enum": ["DEBUG", "INFO", "WARN", "ERROR", "FATAL"] },
    "message": { "type": "string" },
    "service": { "type": "string" },
    "environment": { "type": "string" },
    "trace_id": { "type": "string", "pattern": "^[0-9a-f]{32}$" },
    "span_id": { "type": "string", "pattern": "^[0-9a-f]{16}$" },
    "http": {
      "type": "object",
      "properties": {
        "method": { "type": "string" },
        "path": { "type": "string" },
        "status_code": { "type": "integer" },
        "duration_ms": { "type": "number" }
      }
    }
  }
}
```

### 2.3 Regla de Alerta Multi-Window Multi-Burn-Rate en Prometheus

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: payment-service-slo-alerts
  namespace: monitoring
spec:
  groups:
    - name: payment-service-availability-slo
      rules:
        # Alerta Crítica: Tasa de Consumo 14.4x (Consume el 2% del presupuesto en 1 hora)
        - alert: PaymentServiceErrorBudgetFastBurn
          expr: |
            (
              sum(rate(http_requests_total{job="payment-service",status=~"5.."}[1h]))
              /
              sum(rate(http_requests_total{job="payment-service"}[1h]))
            ) > (14.4 * (1 - 0.999))
            and
            (
              sum(rate(http_requests_total{job="payment-service",status=~"5.."}[5m]))
              /
              sum(rate(http_requests_total{job="payment-service"}[5m]))
            ) > (14.4 * (1 - 0.999))
          for: 2m
          labels:
            severity: page
            slo: availability
          annotations:
            summary: "PaymentService está consumiendo el error budget a una tasa de 14.4x (ventana 1h)"
            description: "Tasa de error elevada detectada en ventanas de 1h y 5m. El sistema agotará el presupuesto en 2 días."
```

### 2.4 Inyección de Latencia de Red con Chaos Mesh (`chaos-mesh-network-delay.yaml`)

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: payment-database-latency
  namespace: production-apps
spec:
  action: delay
  mode: all
  selector:
    namespaces:
      - production-apps
    labelSelectors:
      app.kubernetes.io/name: payment-service
  delay:
    latency: "150ms"
    jitter: "20ms"
    correlation: "50"
  direction: to
  target:
    selector:
      namespaces:
        - database
      labelSelectors:
        app.kubernetes.io/name: postgres-ha
    mode: all
  duration: "10m"
```

### 2.5 NodePool Spot en Karpenter con Consolidación Dinámica

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: spot-compute-pool
spec:
  template:
    spec:
      requirements:
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["spot"]
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64", "arm64"]
        - key: "karpenter.k8s.aws/instance-category"
          operator: In
          values: ["c", "m", "r"]
        - key: "karpenter.k8s.aws/instance-generation"
          operator: Gt
          values: ["5"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default-ec2-nodeclass
      expireAfter: 720h
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 60s
  limits:
    cpu: "1000"
    memory: 2000Gi
```

### 2.6 Despliegue de Inferencia Acelerada con vLLM en GPU

Despliegue de Llama-3-8B optimizado con PagedAttention y usuario sin privilegios sobre GPUs NVIDIA:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vllm-llama3-inference
  namespace: mlops
spec:
  replicas: 2
  selector:
    matchLabels:
      app: vllm-llama3
  template:
    metadata:
      labels:
        app: vllm-llama3
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
      containers:
        - name: inference-engine
          image: vllm/vllm-openai:v0.6.6
          args:
            - "--model"
            - "meta-llama/Meta-Llama-3-8B-Instruct"
            - "--tensor-parallel-size"
            - "1"
            - "--max-model-len"
            - "8192"
            - "--gpu-memory-utilization"
            - "0.90"
            - "--enforce-eager"
          env:
            - name: HUGGING_FACE_HUB_TOKEN
              valueFrom:
                secretKeyRef:
                  name: hf-token-secret
                  key: token
          ports:
            - containerPort: 8000
              name: http
          resources:
            requests:
              cpu: "8"
              memory: "32Gi"
              nvidia.com/gpu: "1"
            limits:
              cpu: "8"
              memory: "32Gi"
              nvidia.com/gpu: "1"
```

### 2.7 Blueprint de Servicio Knative con Escalado a Cero

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: event-processor
  namespace: serverless
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/minScale: "0"
        autoscaling.knative.dev/maxScale: "50"
        autoscaling.knative.dev/target: "100"
        autoscaling.knative.dev/scaleToZeroGracePeriod: "60s"
    spec:
      containerConcurrency: 80
      containers:
        - image: harbor.corp.internal/production/event-processor:v1.2.0
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
          ports:
            - containerPort: 8080
```

---

## 3. Referencia Operativa: Comandos, Diagnósticos y Triage

### 3.1 Verificación de Telemetría e Inspección de Trazas

```bash
# Verificar la salud y consumo de memoria del OpenTelemetry Collector
curl -s http://otel-collector.monitoring.svc.cluster.local:13133/

# Comprobar estado del scrape de métricas en Prometheus
curl -s http://otel-collector.monitoring.svc.cluster.local:8888/metrics | grep otelcol_process_uptime

# Comprobar la propagación del contexto W3C TraceContext mediante curl
curl -v -H "traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01" \
  https://api.bank.corp/v2/payments
```

### 3.2 Aplicación de Políticas de Error Budget y Congelación de Releases

Cuando se dispara una alerta de consumo acelerado (*fast burn*) en producción:

1. **Compuerta Automatizada en CI/CD**: El pipeline consulta las métricas de Prometheus relativas a la tasa de consumo activa del presupuesto de error.
2. **Activación de Congelación de Despliegues**: Si el consumo acumulado a 30 días supera el $100\%$ o la tasa instantánea $> 6.0$, el pipeline de CD bloquea el despliegue de nuevas funcionalidades, autorizando únicamente parches críticos de seguridad o estabilidad.
3. **Redirección de Capacidad de Ingeniería**: La capacidad del sprint se orienta a tareas de fiabilidad, resolución de deuda técnica y mejora de cobertura de pruebas hasta que el SLO móvil recupere el umbral pactado.

### 3.3 Flujos de Trabajo CLI con OpenCost para FinOps

```bash
# Consultar desglose de costes por namespace en Kubernetes durante los últimos 7 días
kubectl cost namespace \
  --window 7d \
  --historical \
  --service-address http://opencost.monitoring.svc.cluster.local:9003

# Calcular la holgura de recursos inactivos en las cargas de trabajo
kubectl cost deployment \
  --show-efficiency \
  --service-address http://opencost.monitoring.svc.cluster.local:9003
```

### 3.4 Verificación en DataOps y NetOps

```bash
# Ejecutar compilación dbt Slim CI únicamente sobre modelos modificados en Git
dbt build \
  --select state:modified+ \
  --defer \
  --state ./target-production-manifest/

# Desplegar y validar una topología de red virtualizada con Containerlab
sudo containerlab deploy --topo templates/xops/containerlab-topo.yaml

# Verificar la convergencia de sesiones BGP dentro de la topología virtual
docker exec -it clab-demo-leaf1 vtysh -c "show ip bgp summary"
```

---

## 4. Mapeo de Referencias y Estándares

### 4.1 Referencia de Plantillas del Repositorio

| Componente | Ruta | Descripción |
| :--- | :--- | :--- |
| OpenTelemetry Collector | `templates/observability/otel-collector-config.yaml` | Configuración multi-pipeline de colector OTLP |
| Logging Estructurado JSON | `templates/observability/structured-log-spec.json` | Esquema JSON monolínea con campos de traza W3C |
| Reglas Prometheus Multi-Burn-Rate | `templates/kubernetes/prometheus-rule-slo-alerts.yaml` | Definición de alertas MWMBR según Google SRE |
| Demora de Red Chaos Mesh | `templates/sre/chaos-mesh-network-delay.yaml` | Inyección declarativa de fallos para pruebas de latencia |
| Política de Error Budget | `templates/sre/error-budget-policy.md` | Política de congelación de despliegues por presupuesto |
| Valores OpenCost K8s | `templates/finops/opencost-k8s-values.yaml` | Asignación de costes en runtime según CNCF |
| NodePool Spot Karpenter | `templates/finops/karpenter-spot-nodepool.yaml` | Diversificación y consolidación dinámica en Spot |
| Despliegue vLLM en GPU | `templates/xops/mlops-vllm-deployment.yaml` | Servidor de inferencia PagedAttention en GPUs NVIDIA |
| Pipeline dbt Slim CI | `templates/xops/dbt-ci-pipeline.yml` | Flujo de CI analítico consciente del estado en Git |
| Topología Containerlab | `templates/xops/containerlab-topo.yaml` | Emulación de red multivendor en pipelines de CI |
| Knative Scale-to-Zero | `templates/xops/knative-service-scale-to-zero.yaml` | Servicio serverless elástico con escalado a cero |

### 4.2 Marcos de Cumplimiento y Operación

- **Manual Google SRE**: Objetivos de nivel de servicio (SLO) y arquitectura de alertas Multi-Window Multi-Burn-Rate.
- **FinOps Foundation FOCUS (FinOps Open Cost and Usage Specification)**: Estandarización de modelos de facturación cloud y contenedores.
- **CNCF CloudEvents v1.0.2**: Especificación universal para metadatos de envoltura de eventos.
- **Convenciones Semánticas de OpenTelemetry**: Estándar W3C TraceContext y nomenclatura semántica de atributos de telemetría.
