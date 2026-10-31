# Infraestructura como Código, Configuración como Código y Database DevOps

## 1. Explicación: Conceptos y Arquitectura

La Infraestructura como Código (IaC) y la Configuración como Código (CaC) transforman el aprovisionamiento de infraestructura física y en la nube en disciplinas formales de ingeniería de software. Las plataformas cloud modernas exigen aislamiento estricto del estado de infraestructura, detección proactiva de desvíos (configuration drift), generación automatizada de imágenes base inmutables y evolución de esquemas de bases de datos sin tiempo de inactividad (zero-downtime).

```text
 ┌────────────────────────────────────────────────────────────────────────┐
 │                      Pull Request del Desarrollador                    │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ Filtros de Calidad CI: TFLint ──► Checkov (IaC SAST) ──► Infracost     │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │ Merge a Trunk (TBD)
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ Motor OpenTofu 1.8+                                                    │
 │  • Cifrado en el Cliente (AES-GCM AEAD vía KMS / PBKDF2)               │
 │  • Bloqueo Distribuido (DynamoDB / Precondiciones de GCS)              │
 └─────────────────┬──────────────────────────────────┬───────────────────┘
                   │                                  │
                   ▼                                  ▼
 ┌──────────────────────────────────┐ ┌───────────────────────────────────┐
 │ Almacenamiento Remoto (S3 / GCS) │ │ Infraestructura Cloud Desplegada  │
 │  • Cifrado Server-Side KMS       │ │  • VPC, EKS, Subredes, Gateways   │
 │  • Versionado y Object Lock      │ │  • Roles IAM de Mínimo Privilegio │
 └──────────────────────────────────┘ └───────────────────────────────────┘
                   ▲
                   │
 ┌─────────────────┴──────────────────────────────────────────────────────┐
 │ Pipeline de Imágenes Golden (Packer + Hardening CIS con Ansible)       │
 │  • Construcción de AMIs inmutables sin acceso SSH en tiempo de runtime │
 └────────────────────────────────────────────────────────────────────────┘
```

### 1.1 Seguridad del Estado Remoto y Bloqueo Concurrente Distribuido

El archivo de estado de Terraform y OpenTofu contiene una representación serializada en JSON de los recursos gestionados, sus metadatos y credenciales sensibles (contraseñas de bases de datos, claves privadas, ARNs y certificados).

#### Vectores de Amenaza del Estado Mal Gestionado

1. **Corrupción de Estado y Condiciones de Carrera**: Sin bloqueo distribuido, ejecuciones concurrentes de `apply` en pipelines de CI entrelazan modificaciones sobre el estado, corrompiendo el grafo de dependencias y dejando recursos huérfanos.
2. **Exposición de Secretos**: Los archivos de estado almacenan atributos en texto plano por diseño. Alojar el estado en buckets públicos o versionarlo en Git expone credenciales críticas de producción.
3. **Eliminación Accidental**: El almacenamiento de objetos sin control de versiones expone la infraestructura a pérdidas irreversibles ante sobreescrituras accidentales.

#### Matriz de Almacenamiento de Estado entre Proveedores Cloud

| Proveedor Cloud | Backend de Almacenamiento | Mecanismo de Bloqueo | Estándar de Cifrado |
| :--- | :--- | :--- | :--- |
| **AWS** | Amazon S3 (Versionado, Privado) | Tabla DynamoDB (Clave de partición `LockID`) | Claves KMS administradas por el cliente (CMK) |
| **Google Cloud** | Google Cloud Storage (GCS) | Precondiciones nativas de generación (`x-goog-if-generation-match`) | Cloud KMS Customer Managed Encryption Keys (CMEK) |
| **Microsoft Azure** | Azure Blob Storage | Concesiones nativas de blobs (Blob Leases) | Azure Key Vault Customer-Managed Keys |

### 1.2 Cifrado Nativo en el Cliente con OpenTofu

Históricamente, Terraform dependía únicamente del cifrado en el lado del servidor (SSE) proporcionado por el proveedor de almacenamiento. Si bien SSE protege los datos en reposo en el bucket, el payload del estado viaja descifrado en tránsito y permanece legible para cualquier rol IAM con permisos de lectura sobre el bucket.

OpenTofu 1.7+ y 1.8+ incorporan **cifrado nativo en el cliente** (`encryption { ... }`). El motor de OpenTofu cifra localmente tanto el archivo de estado como el plan binario mediante AES-GCM (AEAD de 256 bits) antes de transmitirlos al backend remoto. Incluso si el almacenamiento sufriera una brecha de seguridad, los datos del estado resultan completamente ilegibles sin la clave KMS o frase de paso designada.

### 1.3 Configuración como Código (CaC): Imágenes Base Inmutables (Golden Images)

La administración tradicional de servidores se basaba en gestión de configuración mutable (ejecutando Chef, Puppet o Ansible sobre máquinas virtuales vivas en producción). Este enfoque propicia el **desvío de configuración** (*configuration drift*), donde máquinas creadas a partir de la misma plantilla difieren entre sí con el tiempo debido a parches parciales o intervenciones manuales.

La Configuración como Código moderna impone el paradigma de **Infraestructura Inmutable**:
1. **HashiCorp Packer** arranca una instancia de compilación efímera.
2. **Ansible** instala paquetes, configura parámetros del kernel conforme a los benchmarks CIS y asegura el sistema operativo.
3. Se genera un snapshot inmutable de la instancia (AMI en AWS, imagen en GCP/Azure).
4. Los grupos de autoescalado despliegan directamente la imagen inmutable, desactivando accesos SSH interactivos en producción.

### 1.4 Database DevOps (DBDevOps) y el Patrón Expand/Contract

Los contenedores de aplicación sin estado pueden reiniciarse, escalarse o destruirse instantáneamente. En contraposición, las bases de datos relacionales (PostgreSQL, MySQL) conservan el estado transaccional. Modificaciones de esquema no planificadas suelen adquirir bloqueos de tabla exclusivos (`ACCESS EXCLUSIVE`), denegando lecturas y escrituras y provocando caídas masivas del servicio.

#### Las Tres Fases del Patrón Expand/Contract

```text
Fase 1: Expand (Expandir)
┌───────────────────────┐       Coexisten ambas columnas. La aplicación escribe
│ users:                │       tanto en 'name' como en ('first_name', 'last_name').
│  - name (legacy)      │◄───── Las lecturas recurren a 'name' si las nuevas son null.
│  - first_name (nueva) │
│  - last_name (nueva)  │
└───────────────────────┘

Fase 2: Transition (Transición)
┌───────────────────────┐       Un proceso en segundo plano migra los registros históricos.
│ Backfill Asíncrono    │──────►Todas las instancias de aplicación se actualizan para
│ y Doble Escritura     │       leer y escribir únicamente en ('first_name', 'last_name').
└───────────────────────┘

Fase 3: Contract (Contraer)
┌───────────────────────┐       Eliminación segura de la columna obsoleta.
│ users:                │◄───── Ninguna instancia en ejecución referencia
│  - first_name         │       la columna 'name'.
│  - last_name          │
└───────────────────────┘
```

#### Comparativa de Herramientas de Gestión de Esquemas

| Motor | Paradigma | Detección de Bloqueos y Linting | Método de Ejecución | Seguimiento de Estado |
| :--- | :--- | :--- | :--- | :--- |
| **Ariga Atlas** | Declarativo (HCL/SQL) y Versionado | Análisis estático AST nativo y detección de bloqueos | CLI binario independiente en Go / K8s Operator | Tabla `atlas_schema_revisions` |
| **Flyway** | Imperativo (SQL Versionado) | Reglas avanzadas en versión Enterprise comercial | CLI Java / Contenedor / K8s Job | Tabla `flyway_schema_history` |
| **Liquibase** | Declarativo / Imperativo (YAML, XML, SQL) | Conjunto de reglas de calidad configurable | CLI Java / Contenedor / K8s Job | Tabla `DATABASECHANGELOG` |

---

## 2. Guías Prácticas: Blueprints de Producción para IaC, CaC y DBDevOps

### 2.1 Backend Remoto en AWS S3 con Bloqueo en DynamoDB

```hcl
terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }

  backend "s3" {
    bucket         = "enterprise-tfstate-production-us-east-1"
    key            = "workloads/core-infrastructure/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    kms_key_id     = "arn:aws:kms:us-east-1:111122223333:key/mrk-tfstate-key"
    dynamodb_table = "enterprise-tfstate-locks-production"
  }
}
```

### 2.2 Configuración de Cifrado Nativo en el Cliente para OpenTofu 1.8+

El siguiente bloque impone cifrado AES-GCM local sobre archivos de estado y planes de ejecución antes de salir del runner de CI:

```hcl
terraform {
  required_version = ">= 1.8.0"

  encryption {
    key_provider "pbkdf2" "ci_passphrase" {
      passphrase    = var.state_passphrase
      key_length    = 32
      iterations    = 600000
      salt_length   = 32
      hash_function = "sha512"
    }

    method "aes_gcm" "state_encryption" {
      keys = key_provider.pbkdf2.ci_passphrase
    }

    state {
      method   = method.aes_gcm.state_encryption
      enforced = true
    }

    plan {
      method   = method.aes_gcm.state_encryption
      enforced = true
    }
  }
}
```

### 2.3 Plantilla de Golden AMI Inmutable con Packer y Ansible

Automatización del endurecimiento bajo CIS Benchmark para imágenes base Amazon Linux 2023:

```hcl
packer {
  required_version = ">= 1.9.0"
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

source "amazon-ebs" "hardened_node" {
  ami_name      = "golden-ami-al2023-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  instance_type = "t3.medium"
  region        = "us-east-1"

  source_ami_filter {
    filters = {
      name                = "al2023-ami-2023.*-x86_64"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["137112412989"]
  }

  ssh_username = "ec2-user"

  launch_block_device_mappings {
    device_name           = "/dev/xvda"
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name       = "golden-ami-al2023"
    Hardened   = "true"
    ManagedBy  = "packer"
    Compliance = "CIS-Level-1"
  }
}

build {
  name    = "build-hardened-ami"
  sources = ["source.amazon-ebs.hardened_node"]

  provisioner "ansible" {
    playbook_file = "${path.root}/ansible-baseline-hardening.yml"
    user          = "ec2-user"
    extra_arguments = [
      "--extra-vars", "ansible_python_interpreter=/usr/bin/python3"
    ]
  }
}
```

### 2.4 CI/CD Declarativo de Esquemas de Base de Datos con Ariga Atlas

Gestión declarativa del esquema con comprobaciones estáticas de seguridad configuradas en `atlas.hcl`:

```hcl
variable "db_url" {
  type    = string
  default = "postgres://postgres:password@localhost:5432/app_db?sslmode=disable"
}

env "production" {
  src = "file://schema.sql"
  url = var.db_url
  dev = "docker://postgres/16/dev?search_path=public"

  migration {
    dir    = "file://migrations"
    format = atlas
  }

  lint {
    destructive {
      error = true
    }
    concurrent_index {
      error = true
    }
    data_depend {
      error = true
    }
  }
}
```

### 2.5 Job de Migración de Base de Datos en Kubernetes PreSync con Flyway

Integración fluida de migraciones de esquema en flujos de GitOps mediante hooks PreSync de ArgoCD:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: schema-migration-v2-4
  namespace: production-apps
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
      containers:
        - name: flyway-migration
          image: flyway/flyway:10-alpine
          args:
            - -url=jdbc:postgresql://postgres-ha.database.svc.cluster.local:5432/app_db
            - -user=migration_runner
            - -connectRetries=10
            - migrate
          env:
            - name: FLYWAY_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: migration-password
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
```

---

## 3. Referencia Operativa: Comandos y Flujos de Trabajo

### 3.1 Flujo de Trabajo y Ejecución con OpenTofu y Terraform

```bash
# Inicializar el backend y descargar plugins de proveedores
tofu init -reconfigure

# Formatear el código de acuerdo con el estilo canónico
tofu fmt -check -recursive

# Validar la corrección sintáctica y semántica
tofu validate

# Generar un plan de ejecución determinista
tofu plan -out=production.tfplan -input=false

# Aplicar el plan validado controlando la concurrencia
tofu apply -input=false production.tfplan
```

### 3.2 Suite de Validación de Seguridad y FinOps

Comprobaciones locales en fase shift-left antes de abrir Pull Requests:

```bash
# Linting de código Terraform para detectar sintaxis en desuso y malas prácticas
tflint --init
tflint --recursive

# Escanear manifiestos IaC contra vulnerabilidades y fallos en benchmarks CIS
checkov --directory . \
  --framework terraform \
  --output cli \
  --soft-fail=false

# Calcular el impacto presupuestario y delta financiero de los cambios
infracost breakdown --path .
```

### 3.3 Recuperación ante Desastres y Desbloqueo de Estado

Si un pipeline de CI se interrumpe de forma inesperada a mitad de ejecución, el bloqueo del backend remoto puede quedar activo indefinidamente.

```bash
# Inspeccionar el contenido del archivo de estado actual
tofu state pull > recovered-state.json

# Identificar el ID del bloqueo activo a partir del mensaje de error
# Error: Error acquiring the state lock: ConditionalCheckFailedException
# Lock Info: ID: 5f98a72b-426c-d1e9-9fa1-0123456789ab

# Liberar el bloqueo forzosamente tras verificar que no hay otro proceso en curso
tofu force-unlock 5f98a72b-426c-d1e9-9fa1-0123456789ab
```

### 3.4 Flujo Operativo de Esquemas con Ariga Atlas

```bash
# Generar script de migración versionado comparando el esquema declarativo contra migrations/
atlas migrate diff add_orders_table \
  --dir "file://migrations" \
  --to "file://schema.sql" \
  --dev-url "docker://postgres/16/dev?search_path=public"

# Ejecutar comprobaciones automatizadas de seguridad en CI
atlas migrate lint \
  --dir "file://migrations" \
  --dev-url "docker://postgres/16/dev?search_path=public" \
  --latest 1

# Aplicar migraciones pendientes sobre la base de datos de destino
atlas migrate apply \
  --dir "file://migrations" \
  --url "$DATABASE_URL"
```

---

## 4. Mapeo de Referencias y Estándares

### 4.1 Referencia de Plantillas del Repositorio

| Componente | Ruta | Descripción |
| :--- | :--- | :--- |
| Backend S3 y DynamoDB | `templates/terraform/backend-s3-dynamodb.tf` | Backend S3 cifrado con bloqueo distribuido en DynamoDB |
| Backend GCS | `templates/terraform/backend-gcs.tf` | Backend Google Cloud Storage con claves CMEK |
| Backend Azure | `templates/terraform/backend-azurerm.tf` | Backend Azure Blob Storage con arrendamientos nativos |
| Cifrado de Estado OpenTofu | `templates/terraform/opentofu-state-encryption.tf` | Cifrado nativo AES-GCM en el cliente antes de la transmisión |
| Packer Golden AMI | `templates/cac/packer-golden-ami.pkr.hcl` | Generador de AMIs seguras en Amazon Linux 2023 |
| Hardening Base con Ansible | `templates/cac/ansible-baseline-hardening.yml` | Automatización de configuración de SO bajo CIS Nivel 1 |
| Configuración Atlas | `templates/dbdevops/atlas-migration.hcl` | Diffing declarativo de esquemas con análisis de bloqueos |
| Job de Migración Flyway | `templates/dbdevops/flyway-migration-job.yaml` | Tarea batch de migración para hooks PreSync en K8s |

### 4.2 Estándares y Marcos de Cumplimiento

- **CIS Amazon Web Services Foundations Benchmark v3.0.0**:
  - Control 2.1.1: Garantizar cifrado en reposo en todos los buckets S3 con claves gestionadas por el cliente.
  - Control 2.1.2: Garantizar que la política del bucket S3 exija `aws:SecureTransport`.
  - Control 2.1.5: Garantizar la activación del bloqueo de acceso público en buckets S3.
- **CIS Operating System Benchmarks (Level 1 Server)**:
  - Deshabilitación de sistemas de archivos innecesarios y módulos del kernel (`cramfs`, `squashfs`).
  - Restricción de volcados de memoria y habilitación de ASLR (`fs.suid_dumpable = 0`).
  - Hardening del daemon SSH (deshabilitación de login de root, autenticación por contraseña y cifrados débiles).
