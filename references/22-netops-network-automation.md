# NetOps & Network Automation Engineering

## 1. Executive Overview

NetOps (or NetDevOps) applies software engineering, continuous integration, and declarative automation to enterprise and data center network infrastructure. The legacy model of network engineering—manual Secure Shell (SSH) sessions, vendor-proprietary Command Line Interfaces (CLIs), unversioned configuration drift, and scheduled midnight maintenance windows—is incapable of meeting modern cloud-native operational requirements.

In 2025/2026, enterprise network engineering enforces:

- **Network as Code (NaC)**: The entire network state (underlay, overlay, BGP peerings, EVPN-VXLAN fabrics, ACLs) is declared in version-controlled repositories and driven by a Single Source of Truth (SSoT).
- **Modern Management Protocols**: Deprecation of SNMP and CLI screen-scraping in favor of structured, model-driven APIs: **NETCONF**, **RESTCONF**, and **gNMI** (gRPC Network Management Interface).
- **YANG Data Modeling**: Separation of configuration and operational state using vendor-neutral standards (OpenConfig).
- **CI-Driven Network Emulation**: Full multi-vendor network topologies (Arista cEOS, Cisco XRd, FRRouting, Nokia SR Linux) instantiated inside containerized environments via **Containerlab** within GitHub Actions pipelines.

```text
+---------------------------------------------------------------------------------------+
|                               NetOps Automation Lifecycle                             |
+---------------------------------------------------------------------------------------+
|  [ Single Source of Truth (NetBox/Nautobot) ]                                         |
|         |                                                                             |
|         v (Export Host Vars / Fabric Specs)                                           |
|  [ Git Repository: Network-as-Code (Jinja2 / Nornir / Ansible / Terraform) ]          |
|         |                                                                             |
|         v (PR Created)                                                                |
|  [ CI Pipeline: GitHub Actions + Containerlab Emulation ]                            |
|         |                                                                             |
|         +---> [ Spin up virtual Topology (Spine/Leaf cNOS containers) ]               |
|         +---> [ Apply Config via gNMI / NETCONF ]                                     |
|         +---> [ Run Automated Tests: BGP convergence, MTU, PyATS / Batfish ]          |
|         |                                                                             |
|         v (CI Green -> PR Merge)                                                      |
|  [ CD Orchestrator (gNMI Set / Ansible) -> Production Physical Network Switches ]     |
+---------------------------------------------------------------------------------------+
```

---

## 2. Network as Code (NaC) & Programmable Fabrics

### 2.1 The Single Source of Truth (SSoT)

In Network as Code, the physical switch or router is a **replica**, not the primary authority. The definitive state of IP addresses, VLAN allocations, device roles, BGP autonomous system numbers (ASNs), and physical cabling resides in an SSoT platform such as **NetBox** or **Nautobot**.

#### NaC Architectural Workflow

1. **Design Intent**: Engineers submit PRs modifying high-level network design parameters or update NetBox via API.
2. **Template Rendering**: Templating engines (Jinja2, Python Nornir, or Ansible) query NetBox GraphQL/REST endpoints to dynamically render target configurations matching target vendor syntax.
3. **Pre-Deployment Static Validation**: Linters and validation engines (**Batfish**, **pyATS**) evaluate rendered configurations against routing security invariants (e.g., verifying no route leaks, no duplicate IPs, no blackholed prefixes).
4. **Automated Deployment**: Deployment tooling commits the rendered configuration atomically through candidate datastore transactions with automated rollback capabilities.

---

## 3. Telemetry and Management Protocols: NETCONF, RESTCONF & gNMI

Legacy SNMP polling (with 5-minute sampling intervals and arbitrary vendor MIBs) and expect-style CLI scripts fail under microservice and dynamic container workloads. Modern network automation relies on **YANG (RFC 6020 / RFC 7950)** data models transported over secure, transactional RPC protocols.

### 3.1 Comparison Matrix

| Protocol | Transport Layer | Data Encoding | Modeling Language | Streaming Telemetry | Transaction Support | Standard |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **NETCONF** | SSH or TLS (Port 830) | XML | YANG | No (Periodic RPC notifications only) | **Yes** (`candidate`, `running`, `startup` datastores) | RFC 6241 |
| **RESTCONF** | HTTPS (HTTP/1.1 or HTTP/2) | JSON or XML | YANG | Limited (Server-Sent Events) | **No** (Individual HTTP requests per resource) | RFC 8040 |
| **gNMI** | HTTP/2 over TLS (gRPC) | Protocol Buffers (JSON / Protobuf binary) | YANG (OpenConfig) | **Yes** (High-frequency sub-second event streaming) | **Yes** (Atomic Multi-Path `SetRequest`) | OpenConfig Consortium |

---

### 3.2 NETCONF Deep Dive

NETCONF provides a stateful XML-RPC channel supporting distinct configuration datastores:

- `<running/>`: The active configuration running on the network operating system.
- `<candidate/>`: A staging datastore where modifications are made and validated before activating.
- `<startup/>`: The persistent configuration loaded upon device reboot.

#### Transaction Safety Mechanics

1. **Locking**: `<lock><target><candidate/></target></lock>` prevents concurrent write conflicts.
2. **Atomic Modification**: `<edit-config>` targets the candidate datastore.
3. **Pre-commit Validation**: `<validate>` checks schema and hardware constraint compliance.
4. **Atomic Activation**: `<commit>` merges candidate into running.
5. **Rollback Assurance**: `<commit><confirmed/><confirm-timeout>120</confirm-timeout></commit>`. If connectivity is lost or verification fails, the switch automatically rolls back to the previous running configuration after 120 seconds.

```xml
<!-- Example NETCONF <edit-config> payload setting BGP ASN via OpenConfig -->
<rpc message-id="101" xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
  <edit-config>
    <target>
      <candidate/>
    </target>
    <config>
      <network-instances xmlns="http://openconfig.net/yang/network-instance">
        <network-instance>
          <name>default</name>
          <protocols>
            <protocol>
              <identifier xmlns:oc-pol-types="http://openconfig.net/yang/policy-types">oc-pol-types:BGP</identifier>
              <name>bgp</name>
              <bgp>
                <global>
                  <config>
                    <as>65001</as>
                    <router-id>10.0.0.1</router-id>
                  </config>
                </global>
              </bgp>
            </protocol>
          </protocols>
        </network-instance>
      </network-instances>
    </config>
  </edit-config>
</rpc>
```

---

### 3.3 gNMI (gRPC Network Management Interface)

gNMI is an open-source network management protocol developed by Google and the OpenConfig working group. It uses **gRPC** over **HTTP/2**, providing multiplexed, bi-directional streaming and compact binary wire serialization.

#### The Four gNMI RPCs

1. **`Capabilities`**: Discovers the supported YANG models, versions, and encodings of the target switch.
2. **`Get`**: Retrieves snapshots of operational or configuration state paths.
3. **`Set`**: Executes atomic modifications (delete, replace, update) across arbitrary YANG paths in a single transaction.
4. **`Subscribe`**: Opens a continuous streaming telemetry session from the device.

#### gNMI Subscription Modes

- **`ON_CHANGE`**: Switch emits telemetry updates immediately when a hardware state changes (e.g., optical transceiver loss of signal, interface flap, BGP state change). Replaces high-overhead continuous polling.
- **`SAMPLE`**: Emits state periodically at microsecond-to-second intervals (e.g., interface counter bytes in/out).
- **`TARGET_DEFINED`**: Device determines optimal emission mode per leaf model.

```text
+----------------+                       +-----------------------------+
| Telemetry      |  gNMI SubscribeRequest| Arista / Cisco / Nokia      |
| Collector      | --------------------> | Switch (gNMI Target)        |
| (Telegraf /    |                       |                             |
|  Prometheus)   | <-------------------- | Streams Protobuf Updates:   |
|                |   HTTP/2 Stream       | - /interfaces/interface/state|
+----------------+                       | - /bgp/neighbors/state      |
                                         +-----------------------------+
```

#### Automating gNMI with Python (`pygnmi`)

```python
from pygnmi.client import gNMIclient

host = ("10.0.0.1", 57400)
auth = ("admin", "SuperSecurePassword123!")

with gNMIclient(target=host, username=auth[0], password=auth[1], insecure=True) as client:
    # 1. Query device capabilities
    capabilities = client.capabilities()
    print("Supported Models:", [m["name"] for m in capabilities["supported_models"]])

    # 2. Set interface MTU via OpenConfig atomically
    update_payload = [
        (
            "/interfaces/interface[name=Ethernet1]/config/mtu",
            {"openconfig-interfaces:mtu": 9216}
        )
    ]
    result = client.set(update=update_payload)
    print("gNMI Set Result:", result)
```

---

## 4. CI-Driven Network Emulation with Containerlab

Historically, testing network changes required multi-million-dollar physical hardware labs or heavyweight virtual machine hypervisors (GNS3, EVE-NG) that could not execute inside standard cloud CI runners.

**Containerlab** revolutionizes network CI/CD by orchestrating containerized Network Operating Systems (**cNOS**) natively on any Linux host with Docker.

### 4.1 Supported Containerized NOS (cNOS)

- **FRRouting (`frr`)**: High-performance open-source routing suite (BGP, OSPF, IS-IS).
- **Arista cEOS (`arista_ceos`)**: Production Arista EOS image running in a container.
- **Cisco XRd (`cisco_xrd`)**: Containerized Cisco IOS-XR for routing platforms.
- **Nokia SR Linux (`nokia_srlinux`)**: Native microservices-based network operating system.

### 4.2 How Containerlab Works

1. Reads a declarative YAML topology definition.
2. Creates Linux network namespaces and virtual ethernet (`veth`) pairs connecting the container network interfaces.
3. Provisions management IP addresses on a dedicated Linux bridge (`clab-mgmt`).
4. Generates an inventory file for automation frameworks (Ansible, Nornir).

```text
                     Containerlab Spine-Leaf Topology
+-------------------------------------------------------------------------+
| Linux Host / GitHub Actions Runner                                      |
|                                                                         |
|        [ Spine 1 (FRR) ]                      [ Spine 2 (FRR) ]         |
|         /             \                        /             \          |
|    (veth1)          (veth2)               (veth3)          (veth4)      |
|       /                 \                   /                 \         |
|   [ Leaf 1 (cEOS) ]      \                 /      [ Leaf 2 (cEOS) ]     |
|         |                 -----------------               |             |
|    (veth-host1)                                      (veth-host2)       |
|         |                                                 |             |
|   [ Client 1 ]                                      [ Client 2 ]        |
+-------------------------------------------------------------------------+
```

---

### 4.3 End-to-End Network CI Pipeline in GitHub Actions

A complete Network CI pipeline spins up the virtual fabric, configures routing protocols, verifies BGP state, and tests end-to-end data plane reachability:

```yaml
name: Network-as-Code CI Emulation

on:
  pull_request:
    paths:
      - 'network_configs/**'
      - 'topologies/**'

jobs:
  validate-and-emulate:
    runs-on: ubuntu-24.04
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Install Containerlab
        run: |
          bash -c "$(curl -sL https://get.containerlab.dev)"

      - name: Deploy Virtual Network Topology
        run: |
          sudo containerlab deploy --topo templates/xops/containerlab-topo.yaml

      - name: Apply Rendered Configurations via Ansible/gNMI
        run: |
          sudo docker exec clab-spine-leaf-ci-spine1 vtysh -c "show ip bgp summary"
          sudo docker exec clab-spine-leaf-ci-leaf1 vtysh -c "show ip bgp summary"

      - name: Execute Reachability & Convergence Test Suite (pytest)
        run: |
          # Test packet forwarding across fabric between leaf endpoints
          sudo docker exec clab-spine-leaf-ci-leaf1 ping -c 3 192.168.20.2

      - name: Teardown Emulation Topology
        if: always()
        run: |
          sudo containerlab destroy --topo templates/xops/containerlab-topo.yaml --cleanup
```

---

## 5. Summary Checklist for Production Readiness

- [ ] Network Single Source of Truth (NetBox) manages all IPAM, ASN, and topology state.
- [ ] Direct manual CLI configuration of production switches is disabled; all changes flow via Git PRs.
- [ ] Network management transitions to gNMI and NETCONF using standard OpenConfig YANG models.
- [ ] NETCONF deployments mandate `confirmed commit` with automatic rollback timers.
- [ ] Telemetry collectors stream metrics via gNMI `ON_CHANGE` subscriptions rather than SNMP polling.
- [ ] Network modifications are tested inside Containerlab emulation topologies in GitHub Actions prior to merging.
- [ ] Automated verification suites assert routing table convergence, MTU alignment, and BGP peer health.
