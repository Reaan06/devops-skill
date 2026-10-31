# Database DevOps (DBDevOps), Zero-Downtime Migrations & Schema CI/CD

## 1. Executive Overview

In cloud-native continuous delivery, database state represents the single greatest barrier to high-velocity, zero-downtime releases. Stateless containers can be replaced, rolled back, or traffic-shifted in milliseconds; relational databases (PostgreSQL, MySQL) enforce strict schema constraints, transaction semantics, and table locks that can stall production systems during uncoordinated schema alterations.

This reference standardizes:

1. **Database CI/CD Automation**: Integrating declarative schema inspection and imperative versioned migration tools (Ariga Atlas, Flyway, Liquibase) into automated pipelines.
2. **Zero-Downtime Migration Pattern**: Implementing the Expand/Contract (Parallel Run) lifecycle across multi-version application deployments.
3. **Lock Prevention Guardrails**: Eliminating exclusive access locks (`ACCESS EXCLUSIVE`) during schema operations via `CONCURRENTLY` indexing and online schema transformation.
4. **GitOps & Kubernetes Sync Mechanics**: Running transactional database migration jobs as deterministic PreSync hooks within ArgoCD and FluxCD workflows.

---

## 2. DBDevOps Engine Comparison: Atlas, Flyway & Liquibase

### 2.1 Engine Architectural Matrix

| Dimension | Ariga Atlas | Flyway (Redgate) | Liquibase |
| :--- | :--- | :--- | :--- |
| **Paradigm** | Declarative (HCL/SQL) & Versioned | Imperative (Versioned SQL / Java) | Imperative / Declarative (XML, YAML, SQL) |
| **Schema Diffing** | Native AST schema-to-schema engine | External / Proprietary extension | Liquibase Pro Diff / GenerateChangeLog |
| **CI Linting & Safety** | Built-in static analysis (Atlas Lint) | Paid Enterprise Checks | Quality Checks / Rules engine |
| **Execution Model** | Standalone CLI / Go binary / Docker | Standalone CLI / Java JAR / Docker | Standalone CLI / Java JAR / Docker |
| **State Tracking** | `atlas_schema_revisions` table | `flyway_schema_history` table | `DATABASECHANGELOG` & lock table |
| **Kubernetes Operator** | Official Atlas K8s Operator CRDs | Community / Custom Batch Jobs | Liquibase K8s Operator / Batch Jobs |

### 2.2 Ariga Atlas (Declarative & Modern Schema-as-Code)

Atlas allows teams to define the desired schema state in HashiCorp Configuration Language (HCL) or plain SQL DDL. Atlas calculates the minimal safe migration plan:

- **Declarative Migration**: Compares current database schema against desired HCL state and emits plan.
- **Versioned Migration**: Generates forward and backward SQL files tracked in version control (`migrations/`).
- **Dev Database Simulation**: Spins up an ephemeral containerized database during CI to dry-run migrations against real SQL engines, verifying syntax, constraints, and lock risks before approval.

```hcl
// atlas.hcl example configuration
env "local" {
  src = "file://schema.sql"
  dev = "docker://postgres/16/dev"
  migration {
    dir = "file://migrations"
  }
  lint {
    destructive {
      error = true
    }
  }
}
```

### 2.3 Flyway (Imperative Versioned Migration)

Flyway applies ordered SQL scripts named with strict semantic conventions:

- `V1__create_users_table.sql`: Versioned forward migration (immutable once executed).
- `U1__undo_create_users_table.sql`: Optional undo script.
- `R__recreate_views.sql`: Repeatable migration executed whenever its checksum changes.

Flyway stores an MD5/SHA256 checksum in `flyway_schema_history`. If a previously executed migration file is edited in Git, Flyway aborts execution to protect against state divergence.

### 2.4 Liquibase (Multi-Format Formatted Changesets)

Liquibase abstracts database dialects using format-agnostic changesets (YAML, XML, JSON, or SQL). It allows database-independent definitions that translate automatically to target engine dialects (Postgres, Oracle, SQL Server, MySQL):

- Preconditions validate database state before applying changesets.
- Rollback statements are coupled directly inside each change unit.

---

## 3. The Zero-Downtime Migration Pattern: Expand and Contract

Directly renaming a column or dropping an active field causes immediate errors for running application instances (`SELECT column_old FROM ...` returns `column does not exist`).

The **Expand/Contract** (Parallel Run) pattern decomposes a breaking schema change into discrete, backward-compatible deployment phases.

```text
Phase 1: EXPAND            Phase 2: BACKFILL & DUAL-WRITE     Phase 3: CONTRACT
(Release N)                (Background Job / App Logic)       (Release N+1)

┌──────────────┐           ┌────────────────────────────┐     ┌──────────────┐
│ Add nullable │           │ 1. App dual-writes to both │     │ 1. Switch app│
│ column_new   │ ────────► │ 2. Batch-copy old to new   │ ──► │    reads/write│
│ (Old intact) │           │ 3. Backfill verification   │     │ 2. Drop old  │
└──────────────┘           └────────────────────────────┘     └──────────────┘
```

### 3.1 Phase 1: Expand (Additive Schema Modification)

- Add new tables, nullable columns, or columns with non-locking defaults.
- Deploy database migration **before** deploying application code.
- **Invariant**: The running application (Version N) continues operating against `column_old` without failure.

```sql
-- Safe: Add nullable new column without blocking reads/writes
ALTER TABLE orders ADD COLUMN billing_address_json JSONB;
```

### 3.2 Phase 2: Dual-Write & Historical Backfill

1. **Dual-Write Deployment**: Deploy Application Version N+1. When writing customer orders, the application writes to both `billing_address` (legacy text) and `billing_address_json` (new structure), while continuing to read from `billing_address`.
2. **Historical Data Backfill**: Run a throttled background worker to transform and migrate historical rows from `billing_address` to `billing_address_json`:

   ```sql
   -- Throttled batch backfill to avoid lock contention
   UPDATE orders
   SET billing_address_json = json_build_object('raw', billing_address)
   WHERE billing_address_json IS NULL
     AND id BETWEEN 1000000 AND 1050000;
   ```

3. **Validation & Synchronization**: Run checksum or count queries to guarantee 100% parity between legacy and new representations.

### 3.3 Phase 3: Contract (Removal of Legacy Elements)

1. **Switch Read Path**: Deploy Application Version N+2. Reads and writes switch exclusively to `billing_address_json`. Legacy `billing_address` is ignored.
2. **Drop Legacy Artifacts**: Run final schema migration to drop the obsolete column or triggers:

   ```sql
   -- Safe: No active application instances read from this column
   ALTER TABLE orders DROP COLUMN billing_address;
   ```

---

## 4. Database Locking Mechanics & Non-Blocking DDL

In PostgreSQL and MySQL, schema operations (`ALTER TABLE`, `CREATE INDEX`) acquire locks on database catalog objects and table relations. Understanding lock escalation is critical to zero downtime.

### 4.1 PostgreSQL Lock Modes & Pitfalls

| SQL Operation | Lock Mode Acquired | Blocks Reads? | Blocks Writes? | Safe in Production? |
| :--- | :--- | :--- | :--- | :--- |
| `CREATE INDEX` | `SHARE` | No | **Yes** | ❌ Locks all inserts/updates |
| `CREATE INDEX CONCURRENTLY` | `SHARE UPDATE EXCLUSIVE` | No | No | ✅ Safe (requires 2 scans) |
| `ALTER TABLE ADD COLUMN` (no default / null) | `ACCESS EXCLUSIVE` | **Yes** (brief) | **Yes** (brief) | ✅ Safe (catalog only, metadata) |
| `ALTER TABLE ADD COLUMN` with volatile default | `ACCESS EXCLUSIVE` | **Yes** (duration of rewrite) | **Yes** | ❌ Rewrites entire table on disk |
| `ALTER TABLE DROP COLUMN` | `ACCESS EXCLUSIVE` | **Yes** (brief) | **Yes** (brief) | ⚠️ Safe only after read switch |
| `VACUUM FULL` | `ACCESS EXCLUSIVE` | **Yes** | **Yes** | ❌ Replaces table on disk |

### 4.2 Non-Blocking DDL Rules

- **Always Use `CONCURRENTLY` for Indexing**:

  ```sql
  -- NEVER run plain CREATE INDEX on high-traffic tables
  CREATE INDEX CONCURRENTLY idx_users_email ON users(email);
  ```

- **Set Strict Lock Timeouts**:
  Prevent a DDL migration from waiting indefinitely behind long-running analytical queries, which queues subsequent reads and exhausts connection pools:

  ```sql
  SET lock_timeout = '2s';
  ALTER TABLE accounts ADD COLUMN tier VARCHAR(32) DEFAULT 'standard';
  ```

- **Use Online Schema Tools for Giant Tables**:
  For tables with hundreds of millions of rows where DDL locks risk connection saturation, employ shadow-table copy tools:
  - **PostgreSQL**: `pg_repack` (reorganizes tables online without exclusive locks).
  - **MySQL**: `gh-ost` (GitHub Online Schema Transformations) or `pt-online-schema-change` (Percona Toolkit).

---

## 5. CI/CD Migration Linting & Automated Safety Gates

Automating schema linting inside pull requests catches dangerous migration anti-patterns before code touches staging or production.

### 5.1 Critical Linting Rules

1. **Destructive Operations**: Prohibit `DROP TABLE`, `DROP COLUMN`, or `TRUNCATE` in standard feature branches.
2. **Missing Concurrency**: Reject `CREATE INDEX` without `CONCURRENTLY` (PostgreSQL) or `ALGORITHM=INPLACE` (MySQL).
3. **Non-Null Columns without Defaults**: Prohibit `ALTER TABLE ADD COLUMN NOT NULL` without a default value, which fails when table contains existing rows.
4. **Foreign Key Locking**: Adding a foreign key constraint without `NOT VALID` locks the referenced table for validation. Always add constraint with `NOT VALID`, then run `VALIDATE CONSTRAINT` asynchronously.

### 5.2 GitLab / GitHub CI Pipeline Gate Example

```yaml
# Atlas Migration Linting Stage in CI
lint-migrations:
  stage: lint
  image: arigaio/atlas:latest
  script:
    - atlas migrate lint
      --dir "file://migrations"
      --dev-url "docker://postgres/16/dev"
      --latest 1
  rules:
    - changes:
        - migrations/**/*
```

---

## 6. Kubernetes Migration Jobs & GitOps PreSync Hooks

In declarative GitOps pipelines (ArgoCD, FluxCD), database migrations must complete successfully **before** new application pods are deployed. If the migration fails, deployment must abort without rolling out incompatible pods.

```text
Git Commit ──► ArgoCD Sync
                    │
                    ▼
          [PreSync Hook: Flyway / Atlas K8s Job]
                    │
                    ├──► PASS ──► Sync Deployment / Rollout (App v2)
                    │
                    └──► FAIL ──► ABORT SYNC (App v1 remains healthy)
```

### 6.1 ArgoCD PreSync Hook Architecture

- **`helm.sh/hook: pre-install,pre-upgrade`** or **`argocd.argoproj.io/hook: PreSync`**: Instructs the GitOps controller to create and monitor the migration Job before updating `Deployment` or `Rollout` resources.
- **`argocd.argoproj.io/hook-delete-policy: BeforeHookCreation`**: Cleans up previous migration job pods before instantiating the new execution.
- **Exponential Backoff & Failure Handling**: Sets `backoffLimit: 2` to avoid tight crash-loops on persistent schema failures.
- **Credential Sourcing**: Mounts database host, credentials, and SSL certs from encrypted Kubernetes Secrets (`ExternalSecret` or SealedSecret).
