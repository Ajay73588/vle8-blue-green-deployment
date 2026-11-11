# VLE-8 — Blue-Green Deployment using DevOps Tools

End-to-end implementation of **Virtual Lab Experiment 8 (VLE-8): Blue-Green Deployment** using AWS, Terraform, Ansible, Docker, GitHub, Jenkins, and Kubernetes (Minikube).

---

## 1. Project Objective

Implement a production-style Blue-Green Deployment workflow:

`Developer -> GitHub -> Jenkins -> Docker Build -> Kubernetes -> Blue/Green Deployment -> Service Traffic Switching`

Core capabilities:
- Run **Blue (`v1`, 2 replicas)** and **Green (`v2`, 2 replicas)** simultaneously in Kubernetes.
- Route initial production traffic exclusively to **Blue** via `myapp-service`.
- Build, smoke-test, deploy, and independently verify **Green** without sending live traffic to it.
- Pause Jenkins at a **Manual Approval** gate (`Switch production traffic to GREEN?`).
- Switch traffic from **Blue -> Green** via Kubernetes `Service` label selector patching (`color=blue` -> `color=green`).
- Execute instant **Rollback** from **Green -> Blue** (`color=green` -> `color=blue`).

---

## 2. Repository Structure

```text
vle 8/
├── app/                     # Web UI templates, Nginx vhost config, and entrypoint renderer
├── docker/                  # Parameterized Dockerfile (nginx:1.27-alpine)
├── terraform/               # AWS ap-south-1 infrastructure as code (EC2, SG, IAM SSM)
├── ansible/                 # Idempotent server setup (Java, Jenkins, Docker, kubectl, Minikube, Nginx)
├── kubernetes/              # Namespace, Blue Deployment, Green Deployment, and Service manifests
├── jenkins/                 # 11-stage Jenkinsfile with manual approval gate
├── scripts/                 # Deployment, image-loading, traffic-switching, and verification scripts
├── docs/                    # Architecture, implementation notes, and faculty demo / viva guide
├── evidence/                # Real command outputs and browser screenshots captured during testing
├── VLE8_PROGRESS.md         # Phase-by-phase progress & troubleshooting tracker
└── README.md
```

---

## 3. Architecture & Network Design

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for full diagrams and AWS pricing analysis.

- **AWS Region:** `ap-south-1` (Mumbai)
- **Compute:** `c7i-flex.large` (2 vCPU, 4 GiB RAM, Free-Tier eligible on AWS Free Plan) + `30 GiB gp3` encrypted EBS root volume.
- **College Wi-Fi Adaptation:** Outbound TCP `22` (SSH) and `30080` (NodePort) are blocked by the campus firewall, whereas TCP `80`, `443`, and `8080` are open:
  - **Remote Admin & Ansible:** TCP `22` remains closed in the AWS Security Group. All shell access and Ansible execution run over HTTPS (`443`) using **AWS Systems Manager (SSM) Session Manager** (`AWS-StartSSHSession`).
  - **Application Traffic:** Nginx on EC2 (`:80`) reverse-proxies to Minikube's `myapp-service` `NodePort` (`30080`), preserving real Kubernetes Blue-Green routing while exposing the live app at `http://<EC2_PUBLIC_IP>`.

---

## 4. Prerequisites

- AWS CLI v2 + AWS Session Manager Plugin (`session-manager-plugin`)
- Terraform `>= 1.5.0`
- Git
- WSL2 Ubuntu with Ansible (`ansible-core`) for running the playbook over SSH-via-SSM

---

## 5. Infrastructure Setup (Terraform)

All Terraform files live in `terraform/`:
- `providers.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `terraform.tfvars.example`, `.gitignore`

```powershell
# Local Windows PowerShell
cd "terraform"
Copy-Item terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your current public IP (/32)
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply "tfplan"
```

---

## 6. Server Configuration (Ansible)

Configured via `ansible/jenkins_setup.yml` over AWS SSM (`ansible/inventory.ini`):
- 2 GiB swapfile (`vm.swappiness=10`)
- OpenJDK 21 JRE + Jenkins LTS (`-Xms256m -Xmx768m`)
- Docker CE + Buildx (`ubuntu` and `jenkins` added to `docker` group)
- `kubectl` + Minikube (`--driver=docker --cpus=2 --memory=1900mb`)
- Flattened kubeconfig provisioned for `jenkins` at `/var/lib/jenkins/.kube/config`
- Nginx reverse proxy (`:80` -> `<minikube-ip>:30080`) + systemd auto-resume unit

```bash
# Inside WSL2 Ubuntu
cd ansible
ANSIBLE_CONFIG=./ansible.cfg ansible all -m ping -i inventory.ini
ANSIBLE_CONFIG=./ansible.cfg ansible-playbook -i inventory.ini jenkins_setup.yml
```

---

## 7. Application & Docker Build

A single parameterized codebase in `app/` and `docker/Dockerfile` (`nginx:1.27-alpine`) builds both versions using build arguments and explicit tags (never `latest`):

```bash
# Build Blue v1
docker build -f docker/Dockerfile \
  --build-arg APP_COLOR=BLUE --build-arg APP_VERSION=v1 --build-arg BUILD_TAG=blue-v1 \
  -t myapp:v1 .

# Build Green v2
docker build -f docker/Dockerfile \
  --build-arg APP_COLOR=GREEN --build-arg APP_VERSION=v2 --build-arg BUILD_TAG=green-v2 \
  -t myapp:v2 .
```

Endpoints exposed by the container:
- `/` — Blue or Green web dashboard (`Cache-Control: no-store`)
- `/health` — JSON readiness/liveness endpoint (`{"status":"healthy",...}`)
- `/api/info` — Deployment metadata JSON

---

## 8. Kubernetes Deployment

Manifests in `kubernetes/`:
- `namespace.yaml` (`vle8-app`)
- `deployment-blue.yaml` (`myapp-blue`, 2 replicas, `myapp:v1`)
- `deployment-green.yaml` (`myapp-green`, 2 replicas, `myapp:v2`)
- `service.yaml` (`myapp-service`, initially `selector: {app: myapp, color: blue}`)

```bash
bash scripts/deploy-blue.sh
bash scripts/deploy-green.sh
kubectl get deployments,pods,svc,endpoints -n vle8-app -o wide
```

---

## 9. Jenkins Pipeline & GitHub Webhook

`jenkins/Jenkinsfile` implements 11 stages:
1. Checkout
2. Validate Application & Configuration
3. Build Docker Image for Green / `v2` (`myapp:v2-b${BUILD_NUMBER}`)
4. Validate & Test Green Image (container smoke test on `/health`)
5. Deploy Green to Kubernetes
6. Wait for Green Rollout
7. Verify Green Application Independently (`kubectl port-forward`, zero prod traffic)
8. Manual Approval (`Switch production traffic to GREEN?`)
9. Switch Service Selector from Blue to Green
10. Verify Production Traffic Returns `GREEN / v2`
11. Report Deployment Status

Webhook URL format: `http://<EC2_PUBLIC_IP>:8080/github-webhook/` (`application/json`, `Just the push event`, Active).

---

## 10. Blue-Green Switching & Rollback

```bash
# Switch production traffic to Green (v2)
bash scripts/switch-to-green.sh

# Rollback production traffic to Blue (v1)
bash scripts/switch-to-blue.sh
```

> **Note on Zero Downtime:** Switching is instantaneous at the Kubernetes `Service` selector level only when both `myapp-blue` and `myapp-green` pass `readinessProbe` checks (`2/2 Ready`) before patching `myapp-service`. Existing in-flight HTTP keep-alive connections may complete on the previous backend before new requests land on the new selector target.

---

## 11. Verified Live Deployment, Documentation & Evidence

- **GitHub Repository:** `https://github.com/Ajay73588/vle8-blue-green-deployment`
- **EC2 Instance (`ap-south-1`):** `i-07f04268b828911fc` (`c7i-flex.large`, Public IP `43.204.37.176`)
- **Live Application URL:** `http://43.204.37.176` *(left active on **BLUE / v1** for faculty demo)*
- **Jenkins Pipeline UI:** `http://43.204.37.176:8080/job/vle8-blue-green-pipeline/`

### Documentation
- Architecture & Cost Analysis: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Full Implementation Report & Test Matrix (13/13 PASS): [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md)
- Faculty Demo Script & Viva Q&A: [docs/FACULTY_DEMO.md](docs/FACULTY_DEMO.md)
- Progress Tracker: [VLE8_PROGRESS.md](VLE8_PROGRESS.md)

### Evidence Artifacts (`evidence/`)
- **Logs:** [Phase 3 Terraform](evidence/phase3_terraform_outputs.txt), [Phase 4 Ansible](evidence/phase4_ansible_verification.txt), [Phase 5 Docker](evidence/phase5_docker_build_and_test.txt), [Phase 6 Kubernetes](evidence/phase6_kubernetes_verification.txt), [Phase 7 Jenkins Build #3](evidence/phase7_jenkins_build3_console.txt), [Phase 8 GitHub Webhook](evidence/phase8_github_webhook.txt), [Phase 9 Pre-Switch](evidence/phase9_pre_switch_verification.txt), [Phase 9 Green Switch](evidence/phase9_green_switch_verification.txt), [Phase 9 Rollback & Health](evidence/phase9_rollback_and_health.txt)
- **Screenshots:** [Initial BLUE v1](evidence/screenshot_blue_initial.png), [Jenkins Stage View Paused](evidence/screenshot_jenkins_stage_view_paused.png), [Jenkins Manual Approval](evidence/screenshot_jenkins_manual_approval.png), [Switched GREEN v2](evidence/screenshot_green_live.png), [Jenkins Build #3 Success](evidence/screenshot_jenkins_pipeline_success.png), [Rollback BLUE v1](evidence/screenshot_blue_rollback.png)

---

## 12. Pause / Resume & Cleanup (Cost Control)

### Pause between lab & faculty demo (stops EC2 compute billing; keeps EBS & setup)
```powershell
aws ec2 stop-instances --region ap-south-1 --instance-ids <INSTANCE_ID>
```
*(When started again later via `aws ec2 start-instances`, `vle8-minikube-resume.service` automatically restarts Minikube and updates Nginx; if your EC2 Public IP or laptop IP changed, update `terraform.tfvars` and run `terraform apply`.)*

### Full Cleanup (Destroys all AWS resources created by Terraform)
```powershell
cd terraform
terraform destroy
```
*Warning: `terraform destroy` permanently deletes the EC2 instance, 30 GiB EBS volume (Jenkins job history & local Docker images on EC2), IAM role/profile, key pair, and security group. Keep your source code committed to GitHub first.*

