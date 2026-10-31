# Operational Policy: Service Level Objectives (SLOs) & Error Budget Policy

## 1. Purpose & Authority

This Error Budget Policy defines the operational and organizational contract between **Product Management**, **Software Engineering**, and **Site Reliability Engineering (SRE)**.

The primary objective is to replace subjective arguments regarding release cadence with objective, metric-driven constraints. Reliability is treated as a core product feature: when reliability is high, teams ship quickly; when the error budget is depleted, feature delivery yields to stability.

This policy applies across all production workloads and is enforced through automated CI/CD deployment gates and platform governance.

---

## 2. Service Tier Classification & SLO Targets

All services running in production are classified into one of three operational tiers:

| Service Tier | Description | Target Availability SLO (30-Day Rolling) | Target Latency SLO (P99) | Error Budget (30 Days) |
| :--- | :--- | :--- | :--- | :--- |
| **Tier 1: Mission-Critical** | Customer-facing transaction paths, authentication, payment processing | **99.95%** | $\le 200\text{ms}$ | **0.05%** (21.6 min downtime) |
| **Tier 2: Business Core** | Product catalog, user profiles, notification dispatch, search APIs | **99.90%** | $\le 400\text{ms}$ | **0.10%** (43.2 min downtime) |
| **Tier 3: Internal / Async** | Batch reporting, data ingestion pipelines, admin backoffice tools | **99.00%** | $\le 1200\text{ms}$ | **1.00%** (7.2 hrs downtime) |

---

## 3. Mathematical Definitions & SLI Formulations

### 3.1 Availability SLI

The ratio of successful, non-server-error requests to total valid incoming requests:

$$\text{SLI}_{\text{availability}} = \frac{\sum \text{HTTP Requests with Status } < 500}{\sum \text{Total HTTP Requests} - \sum \text{HTTP 4xx (Client Errors)}} \times 100\%$$

### 3.2 Latency SLI

The percentage of valid requests served within the agreed latency threshold:

$$\text{SLI}_{\text{latency}} = \frac{\sum \text{Valid Requests with Duration } \le T_{\text{threshold}}}{\sum \text{Total Valid Requests}} \times 100\%$$

### 3.3 Error Budget Formulation

$$\text{Error Budget} = 100\% - \text{SLO}_{\text{target}}$$

For a Tier 2 service with an SLO of $99.90\%$ over a rolling 30-day window:
- Total seconds in window: $30 \times 24 \times 3600 = 2,592,000\text{ seconds}$
- Maximum permissible downtime or equivalent error seconds: $2,592,000 \times 0.001 = 2,592\text{ seconds}$ ($43\text{ minutes}, 12\text{ seconds}$).

---

## 4. Multi-Window Multi-Burn-Rate Triggers

Alerts and deployment gates are governed by Multi-Window Multi-Burn-Rate (MWMBR) monitoring. Alerts fire only when **both** a short window and a long window exceed the burn rate threshold simultaneously:

| Severity Tier | Burn Rate ($b$) | Budget Consumed | Short Window | Long Window | Operational Action Triggered |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **P0: Emergency** | **14.4x** | 2% in 1 hour | 5 minutes | 1 hour | Page On-Call SRE. **Automated Deployment Freeze**. Incident Commander mobilized. |
| **P1: Critical** | **6.0x** | 5% in 6 hours | 30 minutes | 6 hours | Page On-Call SRE & Engineering Lead. Canary rollbacks triggered automatically. |
| **P2: High** | **3.0x** | 10% in 24 hours | 2 hours | 24 hours | Automated Jira ticket. Review at daily standup. Feature releases restricted. |
| **P3: Moderate** | **1.0x** | 10% in 3 days | 6 hours | 72 hours | Weekly Reliability Review notification. Engineering triage within 48 hours. |

---

## 5. Error Budget Health States & Action Protocol

```text
┌────────────────────────────────────────────────────────────────────────┐
│ State: GREEN (Remaining Budget > 25%)                                  │
│ - Unrestricted deployment velocity.                                    │
│ - Standard progressive canary releases (10% -> 25% -> 50% -> 100%).    │
│ - Chaos engineering experiments permitted in production.               │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
                                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│ State: YELLOW (0% < Remaining Budget <= 25%)                           │
│ - Warning state: Increased deployment scrutiny.                        │
│ - Canary observation windows doubled (from 15m to 30m).                │
│ - Non-essential production chaos experiments suspended.                │
│ - Product teams prepare reliability backlog tickets for next sprint.   │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
                                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│ State: RED (Remaining Budget <= 0% - BUDGET EXHAUSTED)                 │
│ - MANDATORY DEPLOYMENT FREEZE ENFORCED.                                │
│ - Automated CI/CD gates block all non-reliability pull requests.      │
│ - 100% of engineering sprint capacity reallocated to stability.       │
│ - Mandatory blameless post-mortem within 48 hours.                     │
└────────────────────────────────────────────────────────────────────────┘
```

### 5.1 Protocol During Budget Exhaustion (State: RED)

When a service burns $100\%$ of its error budget within the rolling 30-day window:

1. **Automated CI/CD Freeze**:
   - Release pipelines in GitHub Actions and ArgoCD sync windows automatically transition to `Locked`.
   - Pull requests tagged `kind/feature` or `kind/enhancement` are prevented from merging.
2. **Backlog Re-prioritization**:
   - The product roadmap for the affected service is immediately suspended.
   - $100\%$ of engineering sprint bandwidth is reassigned to root-cause remediation, infrastructure hardening, and toil reduction.
3. **Allowed Changes During Freeze**:
   - P0 Hotfixes addressing active production incidents.
   - Critical security vulnerability patches (CVSS $\ge 7.0$).
   - Explicit reliability, performance, or telemetry enhancements approved by the SRE Lead.

---

## 6. Exception & Override Policy

Under extraordinary business circumstances (e.g., critical compliance mandate or severe business emergency), a feature deployment may be requested while the error budget is exhausted.

### 6.1 Approval Matrix

| Override Type | Required Approvers | Quorum Requirement |
| :--- | :--- | :--- |
| **Standard Hotfix / Patch** | SRE On-Call + Engineering Lead | 2 of 2 Approvals |
| **Security CVE Hotfix** | Head of Security + SRE Lead | 2 of 2 Approvals |
| **Emergency Business Override** | **VP of Engineering + SRE Lead + CTO** | **Unanimous (3 of 3)** |

Any emergency business override must be accompanied by an executive risk acknowledgment and a scheduled 24-hour dedicated SRE shadowing shift.

---

## 7. Recovery & Thaw Criteria

A service under a deployment freeze cannot exit the freeze until all of the following criteria are satisfied:

1. **Rolling SLO Recovery**: The service must sustain a measured SLI above the SLO target ($\ge 99.90\%$) for a minimum of **7 consecutive calendar days** without triggering any P0 or P1 burn rate alerts.
2. **Post-Mortem Completion**: A blameless post-mortem must be finalized and published to the organization within **48 hours** of incident resolution.
3. **Remediation Closure**: All identified P0 action items and at least $80\%$ of P1 action items must be implemented, code-reviewed, and verified in staging.
4. **Formal Sign-off**: The SRE Lead and Product Manager must execute a joint sign-off to restore normal CI/CD delivery permissions.

---

## 8. RACI Governance Matrix

| Lifecycle Activity | Product Manager | Engineering Lead | SRE Lead | Incident Commander |
| :--- | :--- | :--- | :--- | :--- |
| **Setting SLO Targets** | Accountable | Consulted | Responsible | Informed |
| **Monitoring SLI & Burn Rates** | Informed | Informed | Responsible | Consulted |
| **Declaring Deployment Freeze** | Informed | Consulted | Accountable | Responsible |
| **Root-Cause Post-Mortem** | Informed | Responsible | Consulted | Accountable |
| **Authorizing Thaw / Unfreeze** | Consulted | Consulted | Accountable | Informed |
| **Toil Backlog Allocation** | Accountable | Responsible | Consulted | Informed |

Legend: R = Responsible, A = Accountable, C = Consulted, I = Informed.
