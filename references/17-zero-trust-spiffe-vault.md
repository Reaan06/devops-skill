# Zero Trust Architecture, SPIFFE/SPIRE Workload Identity, and HashiCorp Vault

## 1. Zero Trust Architecture (ZTA) Principles

Traditional perimeter security ("castle-and-moat") assumes everything inside the corporate intranet or private VPC is trustworthy. **Zero Trust Architecture (NIST SP 800-207)** eliminates implicit trust:

```text
Traditional Perimeter Defense:
[ Untrusted World ] =====( Firewall )=====> [ "Trusted" Intranet: All Workloads Trust Each Other ]

Zero Trust Architecture:
[ Untrusted World ]
       |
       v (Verify Identity & Context)
[ Workload A (SPIFFE ID) ] =====( Mutual TLS 1.3 / Ephemeral Vault Creds )=====> [ Workload B (SPIFFE ID) ]
       ^                                                                                   ^
       |                                                                                   |
       +==================== Continuous Policy & Health Evaluation =======================+
```

### 1.1 Core Tenets of NIST SP 800-207

1. **No Implicit Trust**: Location on the network (IP address, VPC, subnet) does not confer access privileges.
2. **Explicit Cryptographic Identity**: Every workload, human user, and device must prove identity via signed cryptographic tokens.
3. **Least Privilege Enforcement**: Access is granted on a per-session, per-request basis with minimal permissions and short Time-To-Live (TTL).
4. **Dynamic Ephemeral Secrets**: Static credentials (API keys, passwords, long-lived tokens) are eliminated in favor of just-in-time, rotated credentials.

---

## 2. Workload Identity with SPIFFE and SPIRE

The **Secure Production Identity Framework for Everyone (CNCF SPIFFE)** standardizes how distributed workloads identify themselves across dynamic heterogeneous environments without baking static secrets into containers.

### 2.1 The SPIFFE Standard

- **SPIFFE ID**: A uniform resource identifier (URI) representing a workload:
  `spiffe://acme.internal/ns/production/sa/payment-service`
- **SPIFFE Verifiable Identity Document (SVID)**: The cryptographic proof of identity containing the SPIFFE ID.
  - **X.509 SVID**: Digital certificates containing the SPIFFE ID in the `Subject Alternative Name` (SAN) URI field. Used for mTLS authentication.
  - **JWT SVID**: JSON Web Token containing the SPIFFE ID in the `sub` claim. Used for HTTP authorization headers across L7 proxies.
- **SPIFFE Workload API**: A local UNIX domain socket exposed by the node agent where workloads request SVIDs without requiring any bootstrap secrets.

### 2.2 SPIRE Architecture & Workload Attestation

**SPIRE (SPIFFE Runtime Environment)** implements the SPIFFE specification via two components:

```text
                          +------------------------+
                          |      SPIRE Server      |
                          | (CA, Registration API) |
                          +------------------------+
                                      |
                     (Node Attestation: k8s_sat / AWS IID)
                                      v
+-----------------------------------------------------------------------------------+
| Kubernetes Worker Node                                                            |
|                                                                                   |
|  +------------------------+                                                       |
|  |      SPIRE Agent       | (DaemonSet)                                           |
|  +------------------------+                                                       |
|              |                                                                    |
|              v (UNIX Domain Socket: /spiffe-workload-api/spiffe.sock)             |
|   (Workload Attestation: PID, UID, Namespace, ServiceAccount)                     |
|              ^                                                                    |
|              |                                                                    |
|  +------------------------+                                                       |
|  |     Workload Pod       | (App Container fetches X.509 SVID & mTLS keys)        |
|  +------------------------+                                                       |
+-----------------------------------------------------------------------------------+
```

#### Attestation Sequence

1. **Node Attestation**: The SPIRE Agent proves its identity to the SPIRE Server using the Kubernetes Service Account Token (`k8s_sat`) or cloud instance identity document.
2. **Workload Attestation**: When a container contacts `/spiffe-workload-api/spiffe.sock`, the SPIRE Agent interrogates the Linux kernel (`getsockopt` / `SO_PEERCRED`) to extract the caller's PID.
3. **Selector Resolution**: The agent matches the PID to Kubernetes pod metadata (Namespace, ServiceAccount name, container image SHA256).
4. **SVID Delivery**: The agent issues an X.509 SVID signed by the intermediate CA to the workload in-memory, automatically renewing it before expiration.

---

## 3. HashiCorp Vault in High Availability (HA)

HashiCorp Vault provides centralized secret management, encryption as a service, and automated dynamic credential issuance.

```text
               [ Cloud Load Balancer (HTTPS / TLS 1.3) ]
                                   |
                                   v
             +-------------------------------------------+
             |            Active Vault Node              |
             |       (Integrated Raft Leader)            |
             +-------------------------------------------+
               | (Raft Sync: Log Replication & Consensus) |
               +--------------------+---------------------+
                                    |
                    +---------------+---------------+
                    v                               v
    +-------------------------------+   +-------------------------------+
    |       Standby Vault Node 1    |   |       Standby Vault Node 2    |
    |      (Raft Follower / Read)   |   |      (Raft Follower / Read)   |
    +-------------------------------+   +-------------------------------+
```

### 3.1 Integrated Raft Storage

Modern Vault deployments (2025/2026) utilize **Integrated Raft Storage**, removing the operational overhead and security exposure of external databases (Consul, MySQL):

- **Consensus & Resilience**: Raft maintains quorum across an odd number of nodes (typically 3 or 5). Tolerates $(N-1)/2$ node failures.
- **In-Memory Encryption**: Storage writes are encrypted with Vault's AES-256-GCM barrier encryption key before serialization to disk.
- **High Performance Read Replicas**: Standby nodes serve cached read traffic, forwarding mutations to the active leader.

### 3.2 KMS Auto-Unseal

To avoid manual operational bottlenecks during pod recycling and cluster node upgrades, Vault utilizes Cloud Key Management Services (AWS KMS, GCP Cloud KMS, Azure Key Vault) for automated unsealing:

```hcl
seal "awskms" {
  region     = "us-east-1"
  kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/vault-unseal-key"
}
```

On startup, Vault contacts the KMS endpoint to decrypt the master encryption key, unsealing the storage engine without human intervention.

### 3.3 Dynamic Ephemeral Database Credentials

Static database credentials stored in config files or environment variables represent an extreme risk of compromise. Vault's Database Secrets Engine generates unique, just-in-time users with strict TTLs:

```text
[ Microservice ] ===( 1. vault read database/creds/order-role )===> [ Vault Engine ]
                                                                            |
                                               ( 2. CREATE USER 'v_order_9a12' )
                                                                            v
                                                                    [( PostgreSQL )]
[ Microservice ] <===( 3. Returns { username: "v_order_9a12", password: "...", lease_duration: 3600 } )===
```

#### Vault Database Role Configuration

```bash
# Enable database engine
vault secrets enable database

# Configure connection to PostgreSQL
vault write database/config/production-postgres \
    plugin_name=postgresql-database-plugin \
    allowed_roles="readonly-orders" \
    connection_url="postgresql://{{username}}:{{password}}@postgres.internal:5432/orders?sslmode=verify-full" \
    username="vault_admin" \
    password="super-secure-admin-password"

# Define dynamic role with 1-hour lease
vault write database/roles/readonly-orders \
    db_name=production-postgres \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
        GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
    default_ttl="1h" \
    max_ttl="24h"
```

When the lease expires, Vault automatically drops or revokes the PostgreSQL user role, invalidating leaked credentials.

---

## 4. Unifying SPIFFE and Vault

Workloads authenticate to Vault using their cryptographically proven SPIFFE identity:

1. App requests SVID from SPIRE Agent via Workload API.
2. App presents JWT-SVID to Vault's `/v1/auth/jwt` endpoint.
3. Vault validates the JWT-SVID signature against SPIRE Server's public JWKS.
4. Vault issues an ephemeral client token bound strictly to the workload's SPIFFE ID permissions.
5. Workload reads ephemeral database credentials, achieving zero static secrets across the entire lifecycle.
