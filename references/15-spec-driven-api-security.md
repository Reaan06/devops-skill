# Spec-Driven API Security: OpenAPI, GraphQL, gRPC, and Spectral Governance

## 1. Contract-First Security Architecture

Contract-first API development enforces security, validation boundaries, and access control schemas before service implementation. By treating schemas as the single source of truth, automated linters and API Gateways can deterministically reject malformed requests, block unauthorized mutations, and eliminate entire classes of API vulnerabilities at the perimeter.

```text
  [ OpenAPI / GraphQL / gRPC Spec ]
                 |
        (CI Linting & Gates)
                 v
   +---------------------------+
   | Spectral / Buf / ESLint   | ===> Fails build on missing auth, lax types,
   +---------------------------+      or unvalidated object parameters
                 |
                 v (Validated Contract)
   +---------------------------+
   | Envoy / Kong API Gateway  | ===> Enforces request/response schema validation,
   +---------------------------+      JWT scopes, and rate limiting at runtime
                 |
                 v (Clean, Sanitized RPC)
   +---------------------------+
   | Microservice Backend      |
   +---------------------------+
```

---

## 2. Multi-Protocol Schema Security & Linting

### 2.1 OpenAPI 3.1 & Swagger Linting

OpenAPI 3.1 integrates directly with JSON Schema (2020-12 dialect), allowing strict validation definitions:

- **Strict Type Validation**: Every parameter, query string, request body, and response must declare exact types, formats, and boundary constraints (`minimum`, `maximum`, `pattern`).
- **Elimination of Polymorphic Ambiguity**: Avoid unconstrained `anyOf` or `oneOf` without discriminators, which attackers exploit for payload smuggling and parser differential exploits.
- **Mandatory Authentication Schemes**: Every endpoint must explicitly declare applicable `security` scopes (`OAuth2`, `OpenIdConnect`, `mutualTLS`) or deliberately declare an empty array `[]` for authenticated public endpoints with formal justification.

### 2.2 GraphQL Schema Hardening & Linting

GraphQL presents unique attack vectors due to single-endpoint routing (`/graphql`), dynamic query execution, and recursive graph traversal.

#### Hardening Rules via `graphql-eslint`

```yaml
# .graphql-eslint.yml
schema: "./schema/**/*.graphql"
rules:
  "@graphql-eslint/known-type-names": error
  "@graphql-eslint/no-anonymous-operations": error
  "@graphql-eslint/strict-id-in-types":
    - error
    - acceptedIdNames:
        - id
        - _id
  "@graphql-eslint/require-deprecation-reason": warn
```

#### Runtime Attack Mitigations

1. **Query Depth Limiting**: Prevent nested recursive denial-of-service queries (e.g., `user -> friends -> user -> friends`) using `graphql-depth-limit` capped at a depth of 5 to 7.
2. **Query Cost Analysis**: Assign complexity points to fields and reject queries exceeding maximum budget (e.g., via `graphql-cost-analysis` or Apollo Armor).
3. **Disable Schema Introspection in Production**: Disable `__schema` and `__type` queries in staging/production environments to eliminate automated reconnaissance:

```typescript
const server = new ApolloServer({
  schema,
  introspection: process.env.NODE_ENV !== "production"
});
```

### 2.3 gRPC & Protocol Buffers Security with Buf

gRPC uses binary serialization via Protocol Buffers (`.proto`). Security governance is enforced using **Buf**:

#### Buf Configuration (`buf.yaml`)

```yaml
version: v2
modules:
  - path: proto
lint:
  use:
    - STANDARD
  except:
    - PACKAGE_VERSION_SUFFIX
  enum_zero_value_suffix: _UNSPECIFIED
  service_suffix: Service
breaking:
  use:
    - FILE
```

#### Enforcing Protobuf Schema Constraints (protoc-gen-validate / PGV)

```protobuf
syntax = "proto3";

package payment.v1;

import "validate/validate.proto";

message TransferFundsRequest {
  string source_account_id = 1 [(validate.rules).string.uuid = true];
  string target_account_id = 2 [(validate.rules).string.uuid = true];
  int64 amount_cents = 3 [(validate.rules).int64 = {gt: 0, lte: 100000000}];
  string idempotency_key = 4 [(validate.rules).string.pattern = "^[a-fA-F0-9]{32}$"];
}
```

Buf CLI enforces backward compatibility and blocks breaking changes before merging:

```bash
buf lint
buf breaking --against ".git#branch=main"
```

---

## 3. Mitigating the OWASP API Security Top 10

Spec-driven security directly neutralizes critical OWASP API flaws:

| OWASP API Top 10 | Primary Attack Vector | Spec-Driven Prevention Mechanism |
| :--- | :--- | :--- |
| **API1:2023 BOLA** (Broken Object Level Auth) | Manipulating resource IDs (`/orders/{id}`) to access other tenants' data. | Enforce structured UUID formats and gateway tenant context tokens on all resource paths. |
| **API3:2023 BOPLA** (Mass Assignment) | Injecting privileged fields (`isAdmin: true`, `role: superuser`) into update endpoints. | Enforce `additionalProperties: false` and explicit allowed property lists on all mutation models. |
| **API8:2023 Security Misconfiguration** | Missing CORS, exposed stack traces, plain HTTP URLs, lax TLS ciphers. | Spectral rules enforcing HTTPS schemes, standardized error envelopes, and secure headers. |
| **API9:2023 Improper Inventory Management** | Shadow and zombie APIs (`/v1/debug`, unmonitored legacy endpoints). | Strict spec-to-gateway synchronization and CI blocking on undocumented routes. |

### 3.1 Combating BOLA (Broken Object Level Authorization)

BOLA occurs when an endpoint consumes an identifier from user input without verifying whether the authenticated subject has authorization to access the specific object:

```text
Attacker (User 102) ===> GET /api/v1/invoices/99042 ===> Database Return
[Vulnerability: Code checked authentication (is logged in), but not authorization to invoice 99042]
```

#### Remediation via Architecture

1. **Opaque Subject Claims**: Validate `sub` and tenant `org_id` cryptographically at the API Gateway via JWT verification before routing upstream.
2. **Path Parameter Constraints**: Reject arbitrary integers; mandate UUIDv4 / UUIDv7 with strict regex in OpenAPI to stop sequential ID harvesting:

```yaml
parameters:
  - name: invoiceId
    in: path
    required: true
    schema:
      type: string
      format: uuid
```

### 3.2 Combating Mass Assignment (BOPLA)

When API frameworks deserialize JSON directly into domain ORM entities without an explicit Data Transfer Object (DTO) whitelist, client requests can alter administrative properties:

```json
// Attacker payload to POST /api/v1/profile
{
  "name": "Jane Doe",
  "email": "jane@example.com",
  "is_admin": true,
  "account_balance": 1000000
}
```

#### Remediation via Schema

Enforce `additionalProperties: false` globally across all OpenAPI request models. In JSON Schema / OpenAPI 3.1, this instructs the validator to drop or reject any payload containing unmodeled attributes:

```yaml
components:
  schemas:
    UpdateProfileRequest:
      type: object
      additionalProperties: false
      required:
        - name
        - email
      properties:
        name:
          type: string
          maxLength: 100
        email:
          type: string
          format: email
```

---

## 4. Spectral Rule Automation in CI/CD Pipelines

Stoplight Spectral is an open-source JSON/YAML linter driven by customizable rulesets using JSONPath expressions (`$..properties`).

### 4.1 Production Spectral Pipeline Workflow

```text
[ Developer PR ]
       |
       v
[ Spectral Lint Action ]
       |-- Reads: templates/security/spectral-openapi-ruleset.yaml
       |-- Scans: docs/openapi.yaml / apis/**/*.yaml
       v
[ Violations Detected? ]
       |-- Yes (Severity: ERROR) ===> Exit Code 1 (PR Blocked, SARIF posted)
       `-- No  (Or WARN only)    ===> Continue CI Build
```

### 4.2 Core Spectral Rule Implementations

- **`security-schemes-defined`**: Every operation must declare an explicit security mechanism or formal public authorization tag.
- **`enforce-https-only`**: Target server environments must reject plain `http://` protocols.
- **`no-additional-properties`**: Request models must strictly disallow undeclared properties.
- **`standard-error-envelope`**: Responses with HTTP 4xx and 5xx status codes must follow RFC 7807 (Problem Details for HTTP APIs).
