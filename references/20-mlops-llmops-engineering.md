# MLOps & LLMOps Engineering

## 1. Executive Overview

Machine Learning Operations (MLOps) and Large Language Model Operations (LLMOps) establish rigorous software engineering and DevOps principles across the machine learning lifecycle. Classical DevOps manages stateless binaries and declarative configuration; MLOps and LLMOps must govern a tripartite dependency graph: **Code**, **Data**, and **Model Weights**.

In 2025/2026, enterprise production environments demand:

- **Data & Model Provenance**: Deterministic versioning of multi-terabyte datasets and model weights linked directly to Git commits.
- **Hardware-Accelerated Scheduling**: Deterministic Kubernetes orchestration of scarce accelerator hardware (NVIDIA H100, A100, L40S) via Multi-Instance GPU (MIG) and Time-Slicing.
- **Low-Latency Inference Engines**: High-throughput serving via non-contiguous KV-cache memory management (PagedAttention) and continuous iteration-level request batching.
- **Continuous AI Guardrails & Drift Observability**: Automated prompt injection mitigation, real-time input/output policy enforcement, and statistical drift detection across tabular features and high-dimensional vector embeddings.

```text
+---------------------------------------------------------------------------------------+
|                                  MLOps / LLMOps Lifecycle                            |
+---------------------------------------------------------------------------------------+
|  [ Data Ingestion ]  --->  [ Versioning (DVC) ]  --->  [ Training / Fine-Tuning ]    |
|                                                                  |                    |
|  [ Drift Detection (Evidently) ] <--- [ Serving (vLLM/Triton) ] <-- [ Registry (MLflow) ]
|             |                                    |                                    |
|             +---------> [ NeMo Guardrails ] <----+                                    |
+---------------------------------------------------------------------------------------+
```

---

## 2. Machine Learning Lifecycle: Versioning & Experimentation

### 2.1 Dataset and Model Versioning with DVC

Git is architected for text diffs; tracking gigabyte or terabyte dataset snapshots, checkpoints, and safetensors binaries directly in Git causes severe repository bloat and bandwidth exhaustion. **Data Version Control (DVC)** solves this by separating metadata tracking from binary storage.

#### Core Mechanics of DVC

1. **Pointer Files (`.dvc`)**: Small text files containing unique content hashes (MD5 or BLAKE3), file sizes, and destination paths tracked in Git.
2. **Content-Addressable Storage (CAS)**: Binary payloads stored in remote object storage (Amazon S3, Google Cloud Storage, MinIO, Azure Blob Storage) addressed strictly by hash.
3. **Pipeline DAG (`dvc.yaml`)**: Declarative definitions of processing and training stages with explicit dependency (`deps`) and output (`outs`) tracking, enabling automatic caching and selective re-execution.

```text
Developer Workstation / CI Runner               Remote Storage (S3/GCS/MinIO)
+-------------------------------+              +-----------------------------+
| git commit data.dvc          |              | s3://ml-lake/cache/ab/      |
|                               |  dvc push    |   ab4f9812e4... (Raw Data)  |
| .dvc/cache/ab/ab4f9812e4...  | -----------> |                             |
|       ^                       |              | s3://ml-lake/cache/6c/      |
|       | hardlink / reflink    |              |   6c91a702b8... (Weights)   |
| data/train.parquet            |              +-----------------------------+
+-------------------------------+
```

#### Production DVC Pipeline Specification (`dvc.yaml`)

```yaml
stages:
  preprocess:
    cmd: python src/preprocess.py --input data/raw --output data/processed
    deps:
      - data/raw
      - src/preprocess.py
    params:
      - prepare.max_tokens
      - prepare.vocab_size
    outs:
      - data/processed:
          cache: true
          persist: false

  train:
    cmd: python src/train.py --data data/processed --model-dir models/checkpoints
    deps:
      - data/processed
      - src/train.py
    params:
      - train.learning_rate
      - train.batch_size
      - train.epochs
    outs:
      - models/checkpoints:
          cache: true
    metrics:
      - evaluation/metrics.json:
          cache: false
    plots:
      - evaluation/plots/loss_curve.csv:
          cache: false
          x: step
          y: val_loss
```

#### DVC Operational Commands

```bash
# Initialize DVC in existing Git repository
dvc init

# Configure S3 as remote storage with AWS IAM credentials
dvc remote add -d s3remote s3://production-ml-storage/dvc-store
dvc remote modify s3remote region us-east-1

# Track a large dataset directory
dvc add data/raw_unstructured_corpus/
git add data/raw_unstructured_corpus.dvc .gitignore
git commit -m "feat(data): track raw unstructured text corpus v1.4"

# Push binary data to remote S3
dvc push

# Reproduce pipeline only if dependencies changed
dvc repro
```

---

### 2.2 Experiment Tracking & Model Governance: MLflow vs. Weights & Biases

Systematic experiment tracking captures hyperparameters, environment dependencies, hardware utilization, evaluation metrics, and model artifacts to guarantee full reproducibility.

| Feature Dimension | MLflow Tracking & Registry | Weights & Biases (W&B) |
| :--- | :--- | :--- |
| **Hosting Model** | Open Source, fully self-hostable (K8s/Postgres/S3) or Managed (Databricks) | SaaS-first, enterprise self-hosted Dedicated instance available |
| **Artifact Storage** | Pluggable Object Storage (S3, GCS, ABS, MinIO) | Native W&B Artifacts storage with deduplication |
| **System Telemetry** | Basic CPU/Memory logging via system metrics logger | Millisecond-level GPU SM, Memory, Power, and Temperature profiling |
| **Hyperparameter Sweeps** | External orchestration (Optuna, Ray Tune) integration | Integrated native Sweeps engine (Bayesian, Hyperband, Random) |
| **Model Registry** | Native central model stage/alias management & validation | W&B Model Registry with lineage and audit logging |
| **Security & Airgap** | 100% air-gap capable for regulated defense/finance environments | Requires dedicated on-prem installation or enterprise cloud tier |

#### MLflow Production Tracking Integration

```python
import mlflow
import mlflow.pytorch
import torch

mlflow.set_tracking_uri("https://mlflow.platform.internal")
mlflow.set_experiment("llm-finetuning-mistral-7b")

with mlflow.start_run(run_name="qlora-rank64-alpha128") as run:
    params = {
        "base_model": "mistralai/Mistral-7B-v0.3",
        "lora_r": 64,
        "lora_alpha": 128,
        "learning_rate": 2e-4,
        "optimizer": "adamw_torch",
        "warmup_ratio": 0.03
    }
    mlflow.log_params(params)
    
    # Training Loop Mock
    for epoch in range(3):
        train_loss = 1.45 / (epoch + 1)
        val_perplexity = 4.2 / (epoch + 1)
        mlflow.log_metric("train_loss", train_loss, step=epoch)
        mlflow.log_metric("val_perplexity", val_perplexity, step=epoch)
    
    # Log model artifacts with signature
    mlflow.pytorch.log_model(
        pytorch_model=model,
        artifact_path="model",
        registered_model_name="mistral-7b-domain-adapted"
    )
```

---

## 3. GPU Scheduling & Virtualization in Kubernetes

Modern AI workloads require high-density GPU allocation. Running single inference containers with exclusive access to an 80GB NVIDIA H100 results in low SM (Streaming Multiprocessor) utilization and severe financial waste.

### 3.1 The NVIDIA GPU Operator

The **NVIDIA GPU Operator** automates the management of all NVIDIA software components required to provision GPU nodes in Kubernetes:

1. **NVIDIA Driver Container**: Compiles/loads the NVIDIA kernel module dynamically matching the host Linux kernel.
2. **Container Toolkit (`nvidia-container-runtime`)**: Configures containerd to expose host GPU devices to containers via OCI hook.
3. **NVIDIA Kubernetes Device Plugin**: Discovers GPUs on each node and advertises them as schedulable capacity (`nvidia.com/gpu`).
4. **DCGM Exporter**: Queries the Data Center GPU Manager and exposes comprehensive GPU metrics (SM utilization, NVLink bandwidth, memory usage, ECC errors) to Prometheus on port 9400.
5. **GPU Feature Discovery (GFD)**: Labels Kubernetes nodes automatically with GPU architecture (`nvidia.com/gpu.family: hopper`), model (`nvidia.com/gpu.product: NVIDIA-H100-80GB-HBM3`), and memory capacity.

---

### 3.2 GPU Virtualization: Time-Slicing vs. Multi-Instance GPU (MIG)

```text
        GPU Time-Slicing                            Multi-Instance GPU (MIG)
+-------------------------------+              +-------------------------------+
|         NVIDIA A100           |              |          NVIDIA A100          |
| +---------------------------+ |              | +-----------+   +-----------+ |
| | Context 1 (Active)        | |              | | Instance 1|   | Instance 2| |
| +---------------------------+ |              | | 2g.20gb   |   | 3g.40gb   | |
| | Context 2 (Waiting)       | |              | | Dedicated |   | Dedicated | |
| +---------------------------+ |              | | SMs + HBM |   | SMs + HBM | |
| Shared Memory (No OOM Guard)| |              | +-----------+   +-----------+ |
+-------------------------------+              +-------------------------------+
```

#### Comparison Matrix: Time-Slicing vs. MIG

| Characteristic | GPU Time-Slicing | Multi-Instance GPU (MIG) |
| :--- | :--- | :--- |
| **Underlying Mechanism** | Context switching via hardware scheduler | Hardware partitioning of SMs, memory controllers, and cache |
| **Supported Hardware** | Pascal, Volta, Turing, Ampere, Ada, Hopper | Ampere (A100), Hopper (H100), Blackwell |
| **Fault Isolation** | **None**. Fatal CUDA error in Pod A crashes Pod B | **Full Hardware Isolation**. Crashes in Slice 1 cannot affect Slice 2 |
| **Memory Isolation (QoS)** | **None**. Shared address space. Pod A can cause OOM in Pod B | **Strict Hardware Guarantee**. Fixed HBM slice per instance |
| **Performance Jitter** | High due to temporal preemption latency | Zero noisy-neighbor effects; deterministic compute SLA |
| **Maximum Slices** | Arbitrary configuration (e.g., 10x oversubscription) | Up to 7 independent slices on A100/H100 |
| **Primary Use Case** | Development, non-critical dev environments, small models | Production multi-tenant inference, SLA-backed APIs |

#### Configuring MIG via NVIDIA GPU Operator ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: default-mig-parted-config
  namespace: gpu-operator
data:
  config.yaml: |
    version: v1
    mig-configs:
      all-1g.10gb:
        - devices: [all]
          mig-enabled: true
          mig-devices:
            "1g.10gb": 7
      mixed-inference-training:
        - devices: [0]
          mig-enabled: true
          mig-devices:
            "3g.40gb": 1
            "2g.20gb": 1
            "1g.10gb": 2
```

#### Kubernetes Pod Requesting MIG Resource

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: embedding-service-mig
  namespace: ml-inference
spec:
  nodeSelector:
    nvidia.com/gpu.product: NVIDIA-A100-SXM4-80GB
  containers:
    - name: embedding-server
      image: ghcr.io/huggingface/text-embeddings-inference:1.5
      resources:
        limits:
          nvidia.com/mig-1g.10gb: "1"
          cpu: "2"
          memory: "8Gi"
        requests:
          nvidia.com/mig-1g.10gb: "1"
          cpu: "2"
          memory: "8Gi"
```

---

## 4. LLM Serving: High-Performance Inference Architecture

Traditional deep learning serving frameworks (TorchServe, standard Triton without TensorRT-LLM) treat text generation as static request-response batches. Because autoregressive token generation exhibits variable output lengths, naive batching leads to substantial GPU underutilization due to padding tokens and memory fragmentation.

### 4.1 PagedAttention & The KV Cache Challenge

In Transformer autoregressive generation, each token generated attends to all previous tokens. Computing the attention key and value states repeatedly is prohibitive ($O(N^2)$ complexity). Engines cache these tensors in High-Bandwidth Memory (**KV Cache**).

#### The Memory Bottleneck

1. **Dynamic Length**: Sequence lengths cannot be predicted in advance. Systems historically pre-allocated contiguous memory corresponding to the theoretical maximum context window (e.g., 4096 or 32768 tokens).
2. **Fragmentation Waste**: Up to 60%–80% of GPU memory is wasted on unused pre-allocated capacity or external fragmentation.

#### The PagedAttention Breakthrough (vLLM)

vLLM adapts **Virtual Memory Paging** from operating systems to GPU memory:

- KV Cache is divided into fixed-size **Blocks** (e.g., 16 or 32 tokens per block).
- Blocks are allocated dynamically on-demand as tokens generate.
- Physical blocks are stored in non-contiguous GPU memory pages.
- A **Block Table** maps logical sequence tokens to physical block coordinates.
- Enables **Zero-Copy Memory Sharing** for parallel sampling (Beam Search, multiple completions) and shared prompt prefix caching.

```text
Logical Sequence:  [Token 0 ... 15]  [Token 16 ... 31]  [Token 32 ... 47]
                         |                    |                    |
Block Table:          Block 3              Block 7              Block 1
                         |                    |                    |
Physical Memory:   [ Physical Block 1 ]  [ Physical Block 3 ]  [ Physical Block 7 ]
                   (Non-contiguous GPU High-Bandwidth Memory Allocation)
```

---

### 4.2 Continuous Batching (Iteration-Level Scheduling)

Static batching waits for every sequence in a batch to complete before emitting responses and accepting new work. A single request generating 1000 tokens stalls 7 requests generating 20 tokens.

**Continuous Batching** operates at the iteration (token) level:

- After every forward pass (one token generation step), completed sequences are ejected immediately.
- Incoming queued requests are inserted into the running batch at the next token iteration.
- Eliminates "bubble" idle time on GPU execution units, multiplying serving throughput by $3\times$ to $5\times$.

```text
Static Batching:
Seq A: [T1][T2][T3][T4][T5][T6][T7][T8] -> Done
Seq B: [T1][T2]------------------------ (Padded idle GPU time)
Batch finishes only after Seq A completes.

Continuous Batching:
Iteration 1: [Seq A: T1] [Seq B: T1]
Iteration 2: [Seq A: T2] [Seq B: T2] (Seq B finishes)
Iteration 3: [Seq A: T3] [Seq C: T1] (Seq C joins immediately)
```

---

### 4.3 Serving Engine Comparison Matrix

| Engine | Core Backend | Strengths | Ideal Enterprise Deployment |
| :--- | :--- | :--- | :--- |
| **vLLM** | Python / C++ / CUDA kernels | Fast setup, native PagedAttention, native OpenAI API compatibility, speculative decoding, AWQ/GPTQ/FP8 | Rapid deployment, microservices, dynamic LoRA adapters |
| **NVIDIA Triton Inference Server** | C++ with TensorRT-LLM backend | Maximum raw throughput, NVLink optimization, C++ in-process execution, ensemble pipelines | Large enterprise production, strict SLA, massive scale |
| **KServe (v2 Data Plane)** | Pluggable (vLLM, Triton, TorchServe) | Kubernetes-native CRD (`InferenceService`), Knative scale-to-zero, Canary traffic splitting | Multi-model platform running on Kubernetes |

---

## 5. Guardrails & Drift Monitoring

Deploying Large Language Models and ML models into production without deterministic validation exposes the enterprise to prompt injections, data leakage, and silent accuracy degradation.

### 5.1 Prompt Injection Defense with NeMo Guardrails

**NVIDIA NeMo Guardrails** places an unbypassable, programmable security boundary around the LLM using **Colang** modeling language.

```text
User Query ---> [ Input Rails ] ---> [ Core LLM ] ---> [ Output Rails ] ---> Client
                      |                                       |
           (Jailbreak Detection,                     (Hallucination Check,
            PII Redaction, Intent)                    Fact-Checking, Masking)
```

#### Production Guardrail Configuration (`rails.co`)

```yaml
# config.yml
models:
  - type: main
    engine: vllm
    model: meta-llama/Llama-3.1-8B-Instruct
    parameters:
      endpoint: "http://vllm-serving.ml-inference.svc.cluster.local:8000/v1"

rails:
  input:
    flows:
      - check jailbreak
      - mask pii
  output:
    flows:
      - check sensitive data leakage
      - check factual consistency
```

```colang
# rails.co
define flow check jailbreak
  user ...
  $is_jailbreak = execute check_jailbreak_classifier
  if $is_jailbreak
    bot refuse jailbreak attempt
    stop

define bot refuse jailbreak attempt
  "I cannot fulfill this request as it violates security policies."

define flow mask pii
  user ...
  $sanitized_input = execute redact_pii_entities
  user $sanitized_input
```

---

### 5.2 Model and Data Drift Detection with Evidently AI

Over time, real-world data drifts away from the training distribution (**Covariate Shift**) or the relationship between inputs and target variables shifts (**Concept Shift**).

#### Statistical Metrics for Drift Detection

1. **Wasserstein Distance (Earth Mover's Distance)**: Measures the minimum work required to transform one probability distribution into another; ideal for continuous numerical features.
2. **Kolmogorov-Smirnov (K-S) Test**: Non-parametric test comparing cumulative distribution functions; flags drift when $p < 0.05$.
3. **Population Stability Index (PSI)**: Standard in financial risk; $PSI < 0.1$ (no drift), $0.1 \le PSI < 0.2$ (moderate drift), $PSI \ge 0.2$ (significant drift requiring retraining).
4. **Embedding Drift via Cosine Distance**: Projects high-dimensional text/image embeddings and evaluates semantic cluster centroid displacement.

#### Automated Drift Evaluation Script

```python
import pandas as pd
from evidently.report import Report
from evidently.metric_preset import DataDriftPreset, TargetDriftPreset
from evidently.test_suite import TestSuite
from evidently.tests import TestNumberOfDriftedColumns

reference_data = pd.read_parquet("s3://ml-features/reference_train_baseline.parquet")
current_production_data = pd.read_parquet("s3://ml-features/inference_window_last_7d.parquet")

# 1. Generate Analytical Drift Report
drift_report = Report(metrics=[
    DataDriftPreset(drift_share=0.2), # Trigger if 20% of features drift
    TargetDriftPreset()
])
drift_report.run(reference_data=reference_data, current_data=current_production_data)
drift_report.save_html("/var/reports/data_drift_report.html")

# 2. Automated CI/CD Assertion Gate
test_suite = TestSuite(tests=[
    TestNumberOfDriftedColumns(lt=3) # Fail pipeline if 3 or more columns drifted
])
test_suite.run(reference_data=reference_data, current_data=current_production_data)

if not test_suite.as_dict()["summary"]["all_passed"]:
    raise SystemExit("CRITICAL: Significant Data Drift Detected! Automated trigger for retraining pipeline.")
```

---

## 6. Summary Checklist for Production Readiness

- [ ] Datasets and models are tracked in DVC with pointers committed to Git; binary storage backed by S3/GCS.
- [ ] Experiment runs are logged to centralized MLflow or W&B with code commit SHAs and parameter tracking.
- [ ] Kubernetes GPU nodes run the NVIDIA GPU Operator with DCGM metrics scraped by Prometheus.
- [ ] Production workloads utilize Multi-Instance GPU (MIG) for strict hardware SLA and fault isolation.
- [ ] LLM inference engines (vLLM / Triton) enforce PagedAttention and continuous batching.
- [ ] Input prompts pass through NeMo Guardrails or equivalent safety filters before reaching LLM weights.
- [ ] Evidently AI monitors inference features and embeddings for statistical drift, triggering automated retraining pipelines.
