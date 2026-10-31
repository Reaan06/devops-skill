# Orquestación con Kubernetes y Arquitectura Cloud-Native

## 1. Explicación: Conceptos y Arquitectura

Kubernetes opera como el plano de control para la infraestructura moderna nativa de la nube. En entornos de producción, la orquestación de contenedores debe trascender los manifiestos declarativos básicos para garantizar **aislamiento a nivel de kernel**, **segmentación de red Zero Trust**, **escalabilidad elástica determinista** y **resiliencia operativa automatizada**.

```text
                                  Internet
                                     │
                                     ▼
                   ┌───────────────────────────────────┐
                   │     Balanceador de Carga Cloud    │
                   └─────────────────┬─────────────────┘
                                     │
                                     ▼
                   ┌───────────────────────────────────┐
                   │    Gateway API / Envoy Proxy      │
                   │ (HTTPRoute / Terminación TLS SNI) │
                   └─────────────────┬─────────────────┘
                                     │
                   ┌─────────────────┴─────────────────┐
                   │   Cilium eBPF / Ambient ztunnel   │
                   │ (mTLS / Filtrado L7 / Encriptado) │
                   └─────────────────┬─────────────────┘
                                     │
     ┌───────────────────────────────┴───────────────────────────────┐
     │ Namespace: production-apps (Enforce: Restricted PSS)          │
     │                                                               │
     │  ┌─────────────────────────────────────────────────────────┐  │
     │  │ Deployment (Clase de Servicio: Guaranteed QoS)          │  │
     │  │  ┌───────────────────────────────────────────────────┐  │  │
     │  │  │ Pod (readOnlyRootFilesystem, nonroot UID 10001)   │  │  │
     │  │  │  • Contenedor: app                                │  │  │
     │  │  │  • Volumen: tmpfs (/tmp)                          │  │  │
     │  │  │  • SecurityContext: drop ALL, RuntimeDefault      │  │  │
     │  │  └───────────────────────────────────────────────────┘  │  │
     │  └────────────────────────────┬────────────────────────────┘  │
     │                               │                               │
     │  ┌────────────────────────────┴────────────────────────────┐  │
     │  │ PodDisruptionBudget (maxUnavailable: 1)                │  │
     │  └─────────────────────────────────────────────────────────┘  │
     │                                                               │
     │  ┌─────────────────────────────────────────────────────────┐  │
     │  │ NetworkPolicy (Aislamiento Total Default-Deny)          │  │
     │  └─────────────────────────────────────────────────────────┘  │
     └───────────────────────────────┬───────────────────────────────┘
                                     │
                                     ▼
     ┌───────────────────────────────────────────────────────────────┐
     │ Controladores de Autoescalado                                 │
     │  • KEDA Operator (Escalado a cero por Prometheus / Colas)     │
     │  • HPA v2 (Escalado horizontal de réplicas)                   │
     │  • VPA (Modo recomendación exclusivamente, sin reinicios)     │
     └───────────────────────────────────────────────────────────────┘
```

### 1.1 Estándares de Seguridad de Pods (PSS) y Control de Admisión

Kubernetes sustituye la obsoleta `PodSecurityPolicy` (PSP) por el controlador nativo **Pod Security Admission (PSA)**, el cual valida la creación de pods contra tres perfiles oficiales definidos por la comunidad:

1. **Privileged**: Permisos completamente irrestrictos. Diseñado exclusivamente para plugins de red del clúster (CNI), controladores de almacenamiento (CSI) y daemons de gestión del nodo.
2. **Baseline**: Política mínimamente restrictiva que previene escaladas de privilegios conocidas (prohíbe namespaces host network/PID y ejecución privilegiada).
3. **Restricted**: Política de máximo endurecimiento conforme a las mejores prácticas de seguridad de contenedores. Obligatoria para todas las cargas de trabajo de aplicaciones en producción.

Bajo el perfil `restricted`, las cargas de trabajo deben ejecutarse como usuarios no root, descartar todas las capacidades del kernel Linux (`ALL`), exigir `readOnlyRootFilesystem: true`, prohibir la escalada de privilegios (`allowPrivilegeEscalation: false`) y habilitar el perfil seccomp predeterminado (`RuntimeDefault`).

### 1.2 Mecánica de Calidad de Servicio (QoS) en Kubernetes

El kubelet asigna una de tres clases de Calidad de Servicio a cada pod en función de la declaración de sus peticiones (`requests`) y límites (`limits`) de recursos:

| Clase QoS | Condición | Prioridad de Desalojo ante Presión en el Nodo | Características de Limitación de CPU (Throttling) |
| :--- | :--- | :--- | :--- |
| **Guaranteed** | `requests == limits` tanto para CPU como para Memoria en todos los contenedores. | Último en ser desalojado. `oom_score_adj = -997`. | Asignación estática por CPU Manager con límites enteros. Elimina fluctuaciones por CFS quota. |
| **Burstable** | `requests < limits`, o peticiones declaradas sin límites correspondientes. | Prioridad intermedia. `oom_score_adj` dinámico entre 2 y 999 según el consumo relativo a la petición. | Limitado por cuota de CFS (Completely Fair Scheduler) al superar la petición de CPU. |
| **BestEffort** | No se especifican ni `requests` ni `limits`. | Primero en ser eliminado por el kernel ante escasez de memoria. `oom_score_adj = 1000`. | Ciclos de CPU estrictamente oportunistas; sujeto a severo throttling y terminación prematura. |

Las cargas de trabajo críticas de producción con acuerdos de nivel de servicio sensibles a la latencia de cola (P99) deben configurarse siempre con la clase de servicio **Guaranteed** para prevenir desalojos imprevistos y problemas de rendimiento por contención de recursos.

### 1.3 Arquitectura de Service Mesh: Sidecar frente a Sidecarless / Ambient

Las mallas de servicios proporcionan TLS mutuo (mTLS) transparente, modelado de tráfico en capa 7 y telemetría distribuida. La arquitectura ha evolucionado desde proxies sidecar dedicados hacia modelos eBPF y de plano de datos ambiental:

- **Modelo Sidecar (Envoy por Pod)**:
  - Inyecta un contenedor proxy auxiliar en cada pod de la aplicación.
  - *Compromisos*: Sobrecarga sustancial de memoria (50–150 MB por pod), incremento en la latencia de inicialización, interdependencias complejas en el ciclo de vida del pod y necesidad de reiniciar pods al actualizar versiones del proxy.
- **Modelo Sidecarless por eBPF (Cilium)**:
  - Aplica políticas de red, balanceo de carga y cifrado L4/L7 directamente en el kernel Linux mediante programas eBPF anclados a sockets y colas `tc` (traffic control).
  - *Compromisos*: Consumo de recursos y latencia prácticamente nulos, pero exige kernels Linux modernos (5.10+) y privilegios de carga eBPF en los nodos del clúster.
- **Modelo Ambient Mesh (Istio Ambient)**:
  - Divide las responsabilidades en dos niveles desacoplados:
    - **Túnel Zero Trust L4 (`ztunnel`)**: DaemonSet compartido por nodo que gestiona mTLS y autenticación básica.
    - **Waypoint Proxy L7**: Instancia dedicada de Envoy desplegada a nivel de namespace o cuenta de servicio para enrutamiento avanzado, reintentos y políticas HTTP.
  - *Compromisos*: Elimina reinicios de pods de aplicaciones en actualizaciones mientras ofrece control granular de capa 7 solo donde sea estrictamente necesario.

### 1.4 Autoescalado de Cargas de Trabajo: Convivencia entre KEDA, HPA y VPA

El autoescalado moderno combina tres componentes complementarios:

1. **Horizontal Pod Autoscaler (HPA v2)**: Modifica horizontalmente el número de réplicas de pods basándose en el consumo medio de CPU/memoria o métricas personalizadas externas.
2. **KEDA (Kubernetes Event-driven Autoscaling)**: Opera como proveedor de métricas externo para HPA, escalando cargas de trabajo según la profundidad de colas de mensajería, eventos de bases de datos o consultas PromQL de Prometheus. De manera crítica, KEDA ofrece capacidad de **escalado a cero** (*scale-to-zero*), imposible con HPA nativo.
3. **Vertical Pod Autoscaler (VPA)**: Ajusta de forma dinámica las peticiones y límites de CPU y memoria basándose en el consumo histórico observado.

#### La Regla Anti-Conflicto en Autoescalado

Ejecutar HPA y VPA simultáneamente sobre las mismas métricas de CPU o memoria genera un bucle de retroalimentación desestabilizador: HPA añade réplicas ante un pico de carga, lo que reduce el consumo por pod individual; acto seguido, VPA reduce los recursos asignados al pod, provocando fallos por estrangulamiento o reinicios cíclicos.

**Regla de Oro de Convivencia en Autoescalado**:
- Emplee HPA o KEDA para gestionar dinámicamente el número horizontal de réplicas.
- Configure VPA estrictamente con `updateMode: "Off"` (modo recomendación). VPA calcula el dimensionamiento óptimo sin desalojar ni reiniciar pods en ejecución. Los equipos de ingeniería o pipelines automatizados consumen estas recomendaciones para calibrar los recursos estáticos.

---

## 2. Guías Prácticas: Manifiestos de Producción en Kubernetes

### 2.1 Especificación de Deployment Hardened (PSS Restricted y Guaranteed QoS)

El siguiente manifiesto ilustra un despliegue de producción que satisface los criterios de PSS Restricted y la clase Guaranteed QoS:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-service
  namespace: production-apps
  labels:
    app.kubernetes.io/name: payment-service
    app.kubernetes.io/part-of: core-banking
spec:
  replicas: 3
  selector:
    matchLabels:
      app.kubernetes.io/name: payment-service
  template:
    metadata:
      labels:
        app.kubernetes.io/name: payment-service
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
        seccompProfile:
          type: RuntimeDefault
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchLabels:
                    app.kubernetes.io/name: payment-service
                topologyKey: kubernetes.io/hostname
      containers:
        - name: application
          image: myorg/payment-service:v2.4.1@sha256:d8c9f53e6b208941fcdb432909fbb34e444458d9cfdb28d6fa7c213f28cf0a85
          imagePullPolicy: IfNotPresent
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
          resources:
            requests:
              cpu: "1000m"
              memory: "1024Mi"
            limits:
              cpu: "1000m"
              memory: "1024Mi"
          ports:
            - containerPort: 8080
              name: http
          startupProbe:
            httpGet:
              path: /healthz/startup
              port: 8080
            failureThreshold: 30
            periodSeconds: 2
          livenessProbe:
            httpGet:
              path: /healthz/liveness
              port: 8080
            periodSeconds: 10
            timeoutSeconds: 2
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /healthz/readiness
              port: 8080
            periodSeconds: 5
            timeoutSeconds: 2
            successThreshold: 1
            failureThreshold: 2
          volumeMounts:
            - name: ephemeral-tmp
              mountPath: /tmp
      volumes:
        - name: ephemeral-tmp
          emptyDir:
            medium: Memory
            sizeLimit: 128Mi
```

### 2.2 Línea Base de NetworkPolicy Zero-Trust en el Namespace

Aplique esta política combinada para bloquear de raíz todo tráfico no inspeccionado entrante y saliente, permitiendo únicamente resolución DNS controlada:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production-apps
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-coredns-egress
  namespace: production-apps
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

### 2.3 Especificación HTTPRoute de Kubernetes Gateway API

La Gateway API reemplaza a los objetos Ingress tradicionales, permitiendo desacoplar la provisión de infraestructura de la gestión declarativa de rutas:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: payment-api-route
  namespace: production-apps
spec:
  parentRefs:
    - name: enterprise-gateway
      namespace: gateway-system
      sectionName: https
  hostnames:
    - "api.bank.corp"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /v2/payments
      filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            set:
              - name: X-Gateway-Routed
                value: "true"
      backendRefs:
        - name: payment-service
          port: 8080
          weight: 100
```

### 2.4 ScaledObject de KEDA con Disparador de Métricas de Prometheus

Escale réplicas horizontalmente a partir del volumen transaccional HTTP real y reduzca la asignación a cero cuando no exista actividad:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: payment-service-scaler
  namespace: production-apps
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: payment-service
  minReplicaCount: 1
  maxReplicaCount: 20
  cooldownPeriod: 300
  pollingInterval: 15
  triggers:
    - type: prometheus
      metadata:
        serverAddress: http://prometheus-k8s.monitoring.svc.cluster.local:9090
        metricName: http_requests_per_second
        query: sum(rate(http_requests_total{app="payment-service"}[2m]))
        threshold: "150"
        activationThreshold: "5"
```

### 2.5 Presupuesto de Disrupción de Pods (PodDisruptionBudget - PDB)

Proteja la disponibilidad del servicio durante operaciones de mantenimiento voluntario (drenado de nodos por actualizaciones del sistema operativo o autoescalado del clúster):

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: payment-service-pdb
  namespace: production-apps
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: payment-service
```

---

## 3. Referencia Operativa: Comandos, Diagnóstico y Triage

### 3.1 Validación Previa de Manifiestos (Pre-Flight Checks)

Valide la sintaxis YAML y la conformidad con los esquemas formales de OpenAPI de Kubernetes:

```bash
# Validar manifiestos contra esquemas oficiales de OpenAPI de Kubernetes
kubeconform \
  -strict \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  -summary \
  templates/kubernetes/*.yaml

# Ejecutar simulación de aplicación en el servidor (server-side dry run)
kubectl apply --server-side --dry-run=client -f templates/kubernetes/deployment-hardened.yaml
```

### 3.2 Empaquetado y Verificación de Esquemas en Helm

```bash
# Verificar valores contra el esquema JSON Schema del chart
helm lint templates/helm/app-chart

# Renderizar plantillas localmente para inspeccionar los manifiestos generados
helm template test-release templates/helm/app-chart \
  --values templates/helm/app-chart/values.yaml \
  --validate
```

### 3.3 Triage Diagnóstico: Modos de Fallo Habituales

#### 1. CrashLoopBackOff

- **Causa**: El proceso de la aplicación finaliza abruptamente tras el arranque del contenedor.
- **Comandos de Diagnóstico**:

  ```bash
  # Consultar los registros anteriores del contenedor antes del reinicio
  kubectl logs deployment/payment-service -n production-apps --previous

  # Inspeccionar el código de salida y motivo de finalización
  kubectl describe pod <pod_name> -n production-apps | grep -A 10 "Last State:"
  ```

- **Resolución**:
  - Código `1`: Error general de aplicación; verificar traza de excepción en registros anteriores.
  - Código `126`: El comando no posee permisos de ejecución en el sistema de archivos.
  - Código `127`: El ejecutable no existe o la ruta especificada es incorrecta.

#### 2. OOMKilled (Código de Salida 137)

- **Causa**: El contenedor superó la cuota declarada en `resources.limits.memory` o la memoria física del nodo se agotó por completo.
- **Comandos de Diagnóstico**:

  ```bash
  # Confirmar si el pod fue terminado por el gestor OOM del kernel
  kubectl get pod <pod_name> -n production-apps -o jsonpath='{.status.containerStatuses[*].lastState.terminated.reason}'

  # Evaluar el consumo de memoria en tiempo real por contenedor
  kubectl top pod <pod_name> -n production-apps --containers
  ```

- **Resolución**: Reajuste las peticiones y límites de memoria basándose en las métricas de VPA o investigue fugas de memoria en la aplicación.

#### 3. Violaciones de Admisión de Seguridad de Pods (PSA Violations)

- **Causa**: El manifiesto no cumple con la directiva `pod-security.kubernetes.io/enforce: restricted` del namespace.
- **Comandos de Diagnóstico**:

  ```bash
  # Consultar eventos de advertencia y rechazo de creación de pods
  kubectl get events -n production-apps --field-selector reason=FailedCreate
  ```

- **Resolución**: Asegúrese de que `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `runAsNonRoot: true` y `capabilities.drop: ["ALL"]` estén declarados en todos los contenedores del pod.

---

## 4. Mapeo de Referencias y Estándares

### 4.1 Referencia de Plantillas del Repositorio

| Componente | Ruta | Descripción |
| :--- | :--- | :--- |
| Deployment Hardened | `templates/kubernetes/deployment-hardened.yaml` | PSS Restricted, Guaranteed QoS, probes Liveness/Readiness/Startup |
| NetworkPolicy Default-Deny | `templates/kubernetes/network-policy-default-deny.yaml` | Bloqueo perimetral integral de ingress y egress |
| NetworkPolicy L7 Cilium | `templates/kubernetes/cilium-networkpolicy-l7.yaml` | Filtrado HTTP a nivel de path y verbo mediante eBPF |
| HTTPRoute Gateway API | `templates/kubernetes/gateway-api-httproute.yaml` | Enrutamiento avanzado desacoplado de capa 7 |
| ScaledObject KEDA | `templates/kubernetes/keda-scaledobject-prometheus.yaml` | Escalado reactivo por eventos con soporte scale-to-zero |
| Recomendación VPA | `templates/kubernetes/vpa-recommendation.yaml` | Dimensionamiento seguro sin desalojos automáticos |
| PodDisruptionBudget | `templates/kubernetes/pdb.yaml` | Restricciones de alta disponibilidad en mantenimiento |
| Istio Ambient Mesh | `templates/kubernetes/istio-ambient-peerauthentication.yaml` | mTLS estricto mediante túnel ztunnel ambiental |
| External Secrets Operator | `templates/kubernetes/external-secrets-operator.yaml` | Sincronización de secretos desde KMS/Vault a Secrets nativos |
| Helm Chart Empresarial | `templates/helm/app-chart/` | Chart de Helm con validación estricta de JSON Schema |

### 4.2 Estándares y Marcos de Cumplimiento

- **Kubernetes Pod Security Standards**: Especificación del perfil Restricted.
- **CIS Kubernetes Benchmark v1.8.0**:
  - Control 5.2.1: Minimizar la admisión de contenedores con privilegios.
  - Control 5.3.1: Garantizar el establecimiento de NetworkPolicies default-deny.
  - Control 5.4.1: Priorizar almacenamiento de secretos mediante proveedores KMS externos sobre etcd plano.
