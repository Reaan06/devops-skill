# DataOps & Pipeline Engineering

## 1. Executive Overview

DataOps applies Agile development, DevOps automation, and statistical process control to data lifecycle engineering. Traditional data engineering suffers from brittle batch pipelines, silent data corruption, unannounced schema mutations by upstream software teams, and long cycle times for analytics delivery.

In 2025/2026, enterprise DataOps enforces:

- **End-to-End Schema Contracts**: Producer-side schema enforcement preventing upstream breaking changes from polluting analytical lakes and warehouses.
- **Continuous Integration for Transformation (dbt CI/CD)**: Ephemeral PR staging environments, state-aware Slim CI (`state:modified+`), and automated unit/integration tests before merging.
- **Modern Containerized Orchestration**: Declarative asset-oriented DAG execution via Dagster and Kubernetes-native distributed scheduling via Apache Airflow `KubernetesExecutor`.
- **Automated Data Quality Gates**: Multi-tier assertions and statistical anomaly detection via Great Expectations gating pipeline progression.

```text
+---------------------------------------------------------------------------------------+
|                               DataOps Pipeline Architecture                           |
+---------------------------------------------------------------------------------------+
|  [ Upstream App DB / Events ]                                                         |
|         |                                                                             |
|         v (Schema Contract Gate: Protobuf / JSONSchema)                               |
|  [ Ingestion Layer (Kafka / Airbyte / Fivetran) ]                                     |
|         |                                                                             |
|         v (Raw / Bronze)                                                              |
|  [ Orchestrator: Airflow (K8sExecutor) / Dagster (Software-Defined Assets) ]          |
|         |                                                                             |
|         +---> [ Transformation Engine: dbt (Slim CI / Model Contracts) ]              |
|         |                                                                             |
|         v (Curated / Gold)                                                            |
|  [ Data Quality Verification: Great Expectations (Checkpoints & Data Docs) ]          |
|         |                                                                             |
|         v (Passed Quality SLA)                                                        |
|  [ Analytics / BI (Looker / Tableau / Feature Store) ]                                |
+---------------------------------------------------------------------------------------+
```

---

## 2. DataOps Methodology: Contracts, Ephemerality & Testing

### 2.1 The DataOps Guarantees

DataOps elevates data engineering from bespoke manual maintenance to a deterministic software manufacturing discipline:

1. **Reproducibility**: Any data pipeline run can be re-executed deterministically from raw immutable logs for any arbitrary point in time.
2. **Shift-Left Testing**: Schema validation and anomaly detection occur at the producer ingestion boundary, not downstream in analytical dashboards.
3. **Ephemeral Sandbox Isolation**: Developers and pull requests execute in temporary, isolated schema environments without interfering with production analytical datasets.
4. **Data Observability**: Real-time telemetry monitoring the four data golden signals: **Freshness**, **Volume**, **Schema**, and **Distribution**.

---

### 2.2 Schema Contracts: Producer-Side Enforcement

The primary failure mode in enterprise data platforms is an unannounced database migration in an upstream microservice (e.g., column renamed from `user_id` to `account_uuid` or integer timestamp changed to ISO-8601 string).

#### Producer Contract Architecture

Upstream events emitted to event buses (Kafka, Kinesis, Google Pub/Sub) must validate against an immutable schema registry (Confluent Schema Registry or Buf Schema Registry).

```text
[ Application Service ]
       |
       v (Validate Event against Contract)
[ Confluent / Buf Schema Registry ] ---> [ Schema Mismatch: Drop to DLQ + Alert ]
       |
       +--> (Success: Valid Serialization) ---> [ Kafka Topic ] ---> [ Data Lake ]
```

#### dbt Model Contracts (`dbt-core >= 1.5`)

Within the data warehouse (Snowflake, BigQuery, Databricks, PostgreSQL), dbt model contracts enforce strict column data types, constraints, and nullability:

```yaml
version: 2

models:
  - name: dim_customers
    description: "Enterprise golden record for authenticated customer accounts."
    config:
      contract:
        enforced: true
    columns:
      - name: customer_id
        data_type: string
        description: "Primary key UUID."
        constraints:
          - type: not_null
          - type: primary_key
          - type: check
            expression: "length(customer_id) = 36"
      - name: email_address
        data_type: string
        constraints:
          - type: not_null
      - name: lifetime_value_cents
        data_type: integer
        constraints:
          - type: check
            expression: "lifetime_value_cents >= 0"
      - name: created_at_utc
        data_type: timestamp
        constraints:
          - type: not_null
```

When `contract: { enforced: true }` is enabled, dbt generates DDL with strict database constraints and pre-validates query column projections before running `CREATE TABLE` or `INSERT` statements. If a model query omits a specified column or projects an incorrect type, compilation halts immediately.

---

## 3. dbt (Data Build Tool) CI/CD in Production

Executing full dbt builds (`dbt build`) across thousands of production models during a Pull Request is cost-prohibitive and slow. Modern DataOps relies on **Slim CI**.

### 3.1 Slim CI Architecture

Slim CI determines the minimal sub-DAG of models modified in a feature branch compared against the production baseline:

1. **Production Manifest**: Every production dbt run archives its generated `manifest.json` artifact to cloud storage (S3/GCS).
2. **State Comparison**: The CI runner checks out the PR branch, downloads the production `manifest.json`, and executes:

   ```bash
   dbt build --select state:modified+ --defer --state ./state_prod/
   ```

3. **Deferral**: Unmodified upstream parent models are resolved against the production database rather than rebuilt in the PR schema, saving 90%+ compute runtime and cloud warehouse credits.

```text
Production Lineage:
[Raw Orders] ---> [stg_orders] ---> [int_orders] ---> [fct_orders] ---> [finance_dashboard]

Developer modifies ONLY: [int_orders]

Slim CI Execution (--select state:modified+ --defer):
- [stg_orders]: Read from PRODUCTION warehouse (Deferred)
- [int_orders]: Built and tested in EPHEMERAL PR warehouse schema
- [fct_orders]: Built and tested in EPHEMERAL PR warehouse schema
- [finance_dashboard]: Built and tested in EPHEMERAL PR warehouse schema
```

---

### 3.2 Automated Testing Strategy: Schema, Singular & Unit Tests

dbt provides three complementary test layers:

#### 1. Generic Schema Tests (`models/schema.yml`)

Declarative constraints applied to table columns:

```yaml
version: 2

models:
  - name: stg_orders
    columns:
      - name: order_id
        tests:
          - unique
          - not_null
      - name: status
        tests:
          - accepted_values:
              values: ['placed', 'shipped', 'completed', 'cancelled']
      - name: customer_id
        tests:
          - relationships:
              to: ref('stg_customers')
              field: customer_id
```

#### 2. Singular Custom Tests (`tests/assert_order_total_matches_line_items.sql`)

SQL queries that return failing rows (a test passes if and only if zero rows are returned):

```sql
-- Singular test: Order total must equal the sum of line items minus discounts
WITH order_totals AS (
    SELECT order_id, total_amount_cents
    FROM {{ ref('fct_orders') }}
),

line_item_sums AS (
    SELECT
        order_id,
        SUM(price_cents * quantity - discount_cents) AS computed_total_cents
    FROM {{ ref('stg_order_items') }}
    GROUP BY 1
)

SELECT
    o.order_id,
    o.total_amount_cents,
    l.computed_total_cents
FROM order_totals o
JOIN line_item_sums l ON o.order_id = l.order_id
WHERE o.total_amount_cents != l.computed_total_cents
```

#### 3. dbt Unit Tests (`models/unit_tests.yml`)

Introduced in dbt 1.8+, unit tests validate transformation logic against mocked inputs without requiring external warehouse connections:

```yaml
unit_tests:
  - name: test_fct_orders_discount_logic
    model: fct_orders
    given:
      - input: ref('stg_orders')
        rows:
          - {order_id: 1, customer_id: 101, order_date: '2025-01-01'}
      - input: ref('stg_order_items')
        rows:
          - {order_id: 1, price_cents: 5000, quantity: 2, discount_cents: 1000}
    expect:
      rows:
        - {order_id: 1, net_revenue_cents: 9000}
```

---

## 4. Pipeline Orchestration: Airflow vs. Dagster

Modern pipeline orchestrators have evolved from simple CRON schedulers into distributed systems managing execution isolation, state reconciliation, and metadata tracking.

### 4.1 Apache Airflow with KubernetesExecutor

Apache Airflow remains the enterprise standard for task-oriented workflow orchestration. In high-scale deployments, the **KubernetesExecutor** is mandatory:

- **Process Isolation**: Each DAG task runs as an independent, ephemeral Kubernetes Pod.
- **Dependency Sandboxing**: Task A can run in Python 3.9 with PyTorch; Task B runs in Python 3.12 with DuckDB.
- **Dynamic Resource Sizing**: CPU, memory, and GPU limits are defined at the individual task level via `pod_override`.

```text
                    Airflow Architecture (KubernetesExecutor)
+--------------------------------------------------------------------------------+
|  [ Airflow Scheduler ] ---> [ K8s API Server ]                                |
|          ^                                  |                                  |
|          | (Task State Updates)             v (Spawns Ephemeral Pods)          |
|  +---------------+             +---------------------------------------------+ |
|  | Postgres DB   |             | Task Pod 1: (Ingest - Python 3.10, 1Gi RAM) | |
|  +---------------+             | Task Pod 2: (Train - Python 3.12, 1x GPU)   | |
|                                | Task Pod 3: (dbt - dbt-core 1.8, 2Gi RAM)   | |
|                                +---------------------------------------------+ |
+--------------------------------------------------------------------------------+
```

#### Airflow 2.x TaskFlow API DAG with Kubernetes Pod Configuration

```python
from datetime import datetime
from airflow.decorators import dag, task
from kubernetes.client import models as k8s

default_pod_override = k8s.V1Pod(
    spec=k8s.V1PodSpec(
        containers=[
            k8s.V1Container(
                name="base",
                resources=k8s.V1ResourceRequirements(
                    requests={"cpu": "500m", "memory": "1Gi"},
                    limits={"cpu": "1000m", "memory": "2Gi"},
                ),
                security_context=k8s.V1SecurityContext(
                    allow_privilege_escalation=False,
                    run_as_non_root=True,
                    run_as_user=10001,
                ),
            )
        ]
    )
)

@dag(
    schedule="@daily",
    start_date=datetime(2025, 1, 1),
    catchup=False,
    tags=["production", "dataops"],
)
def financial_reconciliation_pipeline():

    @task.kubernetes(
        image="ghcr.io/my-org/dataops-runner:v2.1",
        executor_config={"pod_override": default_pod_override},
    )
    def extract_raw_ledger():
        # Executes isolated container task
        return {"status": "extracted", "records": 450000}

    @task.kubernetes(
        image="ghcr.io/my-org/dbt-runner:v1.8",
        executor_config={"pod_override": default_pod_override},
    )
    def run_dbt_models(upstream_info: dict):
        import subprocess
        subprocess.run(["dbt", "build", "--select", "tag:finance"], check=True)

    extracted_data = extract_raw_ledger()
    run_dbt_models(extracted_data)

financial_reconciliation_pipeline()
```

---

### 4.2 Dagster: Software-Defined Assets (SDA)

Dagster redefines orchestration by focusing on **Data Assets** (tables, machine learning models, file partitions) rather than imperative task DAGs.

#### The Architectural Shift

- **Airflow**: "Run Task A, then run Task B, then run Task C."
- **Dagster**: "I need Asset C. Asset C depends on Asset B, which depends on Asset A. Compute whichever assets are stale or uncomputed."

```python
from dagster import asset, AssetExecutionContext, FreshnessPolicy
import pandas as pd

@asset(
    group_name="finance",
    freshness_policy=FreshnessPolicy(maximum_lag_minutes=60),
)
def raw_payment_transactions() -> pd.DataFrame:
    """Ingests raw transactions from upstream payment gateway API."""
    return pd.read_parquet("s3://raw-lake/payments/2025-01-01.parquet")

@asset(
    group_name="finance",
    deps=[raw_payment_transactions],
)
def clean_payment_transactions(context: AssetExecutionContext) -> pd.DataFrame:
    """Standardizes currencies and strips PII metadata."""
    df = raw_payment_transactions()
    df["amount_cents"] = df["amount_dollars"] * 100
    context.add_output_metadata({"record_count": len(df)})
    return df
```

---

## 5. Data Quality Testing with Great Expectations

**Great Expectations (GX)** is the industry standard for expressive, automated data quality assertions. It establishes executable tests called **Expectations** that evaluate data distributions, missingness, schema types, and business invariants.

### 5.1 Architecture & Core Primitives

```text
+---------------------------------------------------------------------------------------+
|                            Great Expectations Architecture                            |
+---------------------------------------------------------------------------------------+
|  [ Data Source (Postgres / Snowflake / S3) ]                                         |
|                     |                                                                 |
|                     v                                                                 |
|  [ Expectation Suite: JSON/Code Assertions ]                                          |
|      - expect_table_row_count_to_be_between(min, max)                                 |
|      - expect_column_values_to_not_be_null(column)                                    |
|      - expect_column_values_to_match_regex(column, regex)                             |
|                     |                                                                 |
|                     v                                                                 |
|  [ Checkpoint Execution ] ---------------------------------------------------+        |
|                     |                                                        |        |
|                     v (Generate Documentation)                               v        |
|  [ Data Docs (Static HTML S3 Site) ]               [ Failure Actions: PagerDuty/Slack]|
+---------------------------------------------------------------------------------------+
```

### 5.2 Authoring an Expectation Suite

```python
import great_expectations as gx

context = gx.get_context()

# 1. Connect to Data Source
data_source = context.data_sources.add_pandas("financial_lake")
asset = data_source.add_parquet_asset(name="daily_settlements", file_path="s3://lake/settlements.parquet")
batch_request = asset.build_batch_request()

# 2. Define Expectation Suite
suite = context.suites.add(gx.ExpectationSuite(name="settlement_validation_suite"))

# Assertion 1: Total row volume sanity check
suite.add_expectation(
    gx.expectations.ExpectTableRowCountToBeBetween(min_value=10000, max_value=500000)
)

# Assertion 2: Transaction ID uniqueness and completeness
suite.add_expectation(
    gx.expectations.ExpectColumnValuesToNotBeNull(column="transaction_id")
)
suite.add_expectation(
    gx.expectations.ExpectColumnValuesToBeUnique(column="transaction_id")
)

# Assertion 3: Currency code conforms to ISO 4217
suite.add_expectation(
    gx.expectations.ExpectColumnValuesToBeInSet(
        column="currency_code",
        value_set=["USD", "EUR", "GBP", "JPY", "CAD"]
    )
)

# Assertion 4: Fee percentage within realistic bounds
suite.add_expectation(
    gx.expectations.ExpectColumnValuesToBeBetween(
        column="fee_percentage",
        min_value=0.001,
        max_value=0.05
    )
)

# 3. Create Checkpoint with Action List (Alerts & Data Docs)
checkpoint = context.checkpoints.add(
    gx.Checkpoint(
        name="daily_settlement_checkpoint",
        batch_request=batch_request,
        expectation_suite_name="settlement_validation_suite",
        action_list=[
            gx.actions.UpdateDataDocsAction(name="update_docs"),
            gx.actions.SlackNotificationAction(
                name="alert_on_failure",
                slack_webhook="https://hooks.slack.com/services/T00/B00/X00",
                notify_on="failure"
            )
        ]
    )
)

# 4. Execute Checkpoint
result = checkpoint.run()
if not result.is_success():
    raise ValueError("Data Quality SLA Violated! Pipeline execution aborted.")
```

---

## 6. Summary Checklist for Production Readiness

- [ ] Upstream events enforce schema contracts via Protobuf / JSONSchema before reaching analytical lakes.
- [ ] dbt transformation models use `contract: { enforced: true }` for mission-critical dimensional models.
- [ ] CI pipeline utilizes Slim CI (`state:modified+`) with deferred execution against production manifests.
- [ ] Airflow workflows run via `KubernetesExecutor` with strict container resource limits and security contexts.
- [ ] Dagster Software-Defined Assets track data lineage, partition dependencies, and freshness policies.
- [ ] Great Expectations checkpoints run automatically post-ingestion and post-transformation, triggering alerts on SLA breaches.
- [ ] Ephemeral database schemas created for PR testing are automatically destroyed upon PR closure.
