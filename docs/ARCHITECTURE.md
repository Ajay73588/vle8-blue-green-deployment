# VLE-8 Architecture & Cost Design — Blue-Green Deployment

## 1. Network & Access Architecture (College Wi-Fi Constraints)

Diagnostic tests from the local Windows 11 + WSL2 workstation on college Wi-Fi revealed:

| Port / Protocol | Target Tested | Status | Architectural Impact |
|---|---|---|---|
| TCP 22 (SSH) | `github.com:22`, `portquiz.net:22` | **Blocked** | Direct SSH to EC2 is blocked; port 22 is kept **closed** in the Security Group. |
| TCP 443 (HTTPS) | `github.com:443`, `ssh.github.com:443`, `ec2.ap-south-1.amazonaws.com:443`, `ssm.ap-south-1.amazonaws.com:443` | **Open** | GitHub HTTPS pushes, AWS API calls, and **AWS SSM Session Manager** (shell + SSH-over-SSM + port forwarding) work cleanly over 443. |
| TCP 80 (HTTP) | `portquiz.net:80` | **Open** | Demo application is exposed on EC2 port 80 via Nginx reverse-proxying to Minikube's `NodePort` (`30080`). |
| TCP 8080 (HTTP Alt) | `portquiz.net:8080` | **Open** | Jenkins UI and GitHub Webhooks work over port 8080, restricted to the user's IP and official GitHub webhook CIDRs. |
| TCP 30080 (NodePort) | `portquiz.net:30080` | **Blocked** | Direct external access to Kubernetes NodePort `30080` is blocked by campus firewall, so Nginx on EC2 `:80` bridges external HTTP traffic to Minikube `:30080`. |

## 2. System & Blue-Green Traffic Architecture

```mermaid
flowchart LR
  Dev["Developer Workstation (Windows + WSL2)"] -->|"Git Push (HTTPS 443)"| GH["GitHub Repository (VLE-8)"]
  Dev -->|"Ansible SSH-over-SSM (HTTPS 443)"| SSM["AWS Systems Manager (SSM)"]
  GH -->|"Webhook POST (:8080)"| Jenkins["Jenkins Controller (EC2 :8080)"]

  subgraph EC2["AWS EC2 (ap-south-1, Ubuntu 24.04 LTS, c7i-flex.large)"]
    SSM -->|"Local Tunnel / Shell"| HostOS["Ubuntu Host + Docker Engine"]
    Jenkins -->|"Docker Build + kubectl"| K8s
    Nginx["Nginx Reverse Proxy (:80)"] -->|"proxy_pass :30080"| K8s

    subgraph K8s["Minikube Kubernetes Cluster"]
      Svc["Service: myapp-service (selector: color=blue OR color=green)"]
      Blue["Deployment: myapp-blue (2 Pods, v1)"]
      Green["Deployment: myapp-green (2 Pods, v2)"]
      Svc -->|"Active Traffic"| Blue
      Svc -.->|"Switched Traffic after Approval"| Green
    end
  end

  User["Faculty / Demo Browser"] -->|"HTTP :80 (Allowed IP)"| Nginx
```

## 3. Blue-Green Switching & Independent Verification Flow

```mermaid
sequenceDiagram
  participant Dev as Developer
  participant GH as GitHub
  participant J as Jenkins Pipeline
  participant K as Minikube K8s
  participant U as Production Service (:80)

  Note over K,U: Initial State: myapp-service selector color=blue (v1)
  Dev->>GH: Push v2 changes
  GH->>J: Webhook triggers build
  J->>J: Build & test myapp:v2 Docker image
  J->>K: kubectl apply deployment-green.yaml (2 replicas)
  J->>K: Wait for rollout & test Green pods via port-forward (no prod traffic)
  J-->>Dev: Pause at Manual Approval: "Switch production traffic to GREEN?"
  Dev->>J: Approve switch
  J->>K: kubectl patch svc myapp-service (selector color=green)
  U-->>Dev: HTTP :80 now returns GREEN / v2
  Note over K,U: Rollback runs kubectl patch svc myapp-service (selector color=blue)
```

## 4. AWS Sizing & Cost Estimate (`ap-south-1` Mumbai)

Live pricing queried from the AWS Pricing API for `ap-south-1`:

> **Account Constraint Discovered During Provisioning:** The AWS account operates on the AWS Free Plan, which rejects `t3a.medium` (`InvalidParameterCombination: The specified instance type is not eligible for Free Tier`). Among `free-tier-eligible=true` `x86_64` instance types in `ap-south-1`, **`c7i-flex.large`** (2 vCPU, 4 GiB RAM) satisfies the 4 GiB RAM requirement for Minikube + Jenkins + Docker.

| Resource | Specification | Unit Rate (USD) | Hourly Cost | 4-Hour Lab Cost | Monthly (24/7) |
|---|---|---:|---:|---:|---:|
| EC2 Instance | `c7i-flex.large` (2 vCPU, 4 GiB RAM, Free-Tier eligible) | $0.08479 / hr *(On-Demand)* | $0.08479 | $0.339 | ~$61.90 |
| EBS Root Volume | 30 GiB `gp3` (3000 IOPS, 125 MiB/s included) | $0.0912 / GB-mo | ~$0.0037 | ~$0.015 | $2.74 |
| Default VPC / SSM Core / SG | Standard AWS primitives | $0.00 | $0.00 | $0.00 | $0.00 |
| **Total Estimated Cost** | *(if billed On-Demand outside Free-Tier credits)* | — | **~$0.0885 / hr** | **~$0.354** | **~$64.64 / mo** |

### Why `c7i-flex.large` instead of `t2.medium`, `t3a.medium`, or `t3.small`?
- **Vs. `t3a.medium` / `t2.medium`:** Rejected by AWS Free Plan (`free-tier-eligible=true` required by `RunInstances`).
- **Vs. `t3.small` (2 GiB RAM, $0.0224/hr):** Minikube requires ~1.8–2.0 GiB RAM alongside Jenkins JVM (~768 MiB) and Docker builds; 2 GiB total RAM risks OOM kills.
- **Vs. `m7i-flex.large` (8 GiB RAM, $0.10075/hr):** `c7i-flex.large` meets the 4 GiB RAM requirement at lower cost.
- **Avoided expensive resources:** No EKS control plane ($0.10/hr + worker nodes), no NAT Gateway ($0.045/hr+), and no Application/Classic Load Balancer ($0.025/hr+).

