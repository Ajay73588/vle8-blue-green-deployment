# VLE-8 Implementation Report & Verification Evidence

**Project:** VLE-8 — Blue-Green Deployment using DevOps Tools  
**Workspace:** `c:\Users\LENOVO\Downloads\vle 8`  
**GitHub Repository:** `https://github.com/Ajay73588/vle8-blue-green-deployment`  
**AWS Region:** `ap-south-1` (Mumbai)  
**EC2 Instance:** `i-07f04268b828911fc` (`c7i-flex.large`, Public IP `43.204.37.176`)

---

## 1. End-to-End Architecture Summary

This implementation executes the full VLE-8 workflow completely from scratch without reusing any external workspace, AWS resource, Jenkins instance, Kubernetes cluster, or repository:

`Developer (Windows 11 + WSL2) -> GitHub -> Webhook (:8080) -> Jenkins Pipeline -> Docker Build (myapp:v2-b3) -> Minikube K8s (myapp-blue v1 + myapp-green v2) -> Independent Port-Forward Test -> Manual Approval Gate -> myapp-service Selector Switch -> Rollback`

Key engineering adaptations made for the college Wi-Fi network:
1. **SSH Port 22 Blocked -> AWS SSM Session Manager:** TCP port `22` remains closed in the AWS Security Group (`sg-091fad6f971b3c43e`). Interactive shell access (`aws ssm start-session`) and Ansible SSH transport (`ansible/ssm-proxy.sh` via `AWS-StartSSHSession`) both tunnel securely over outbound HTTPS (`443`).
2. **NodePort 30080 Blocked -> Nginx Reverse Proxy on Port 80:** Nginx on the EC2 host listens on `:80` and proxies to `<minikube-ip>:30080`, preserving Kubernetes `myapp-service` selector-based routing while exposing `http://43.204.37.176` cleanly to the user/faculty browser.

---

## 2. Phase-by-Phase Implementation Record

### Phase 1 & 2 — Workstation Diagnosis, Network Testing & Design
- Verified Windows 11 tools: Terraform `v1.16.3`, AWS CLI `2.36.49`, Session Manager Plugin `1.2.896.0`, Git `2.54.0`, Git Credential Manager `2.7.3`, `kubectl v1.36.1`, Node `v24.17.0`.
- Verified WSL2 (`Ubuntu 26.04.1 LTS`): `ansible [core 2.20.1]`, `python3 3.14.4`, `OpenSSH 10.2p1`.
- Network probe from campus Wi-Fi confirmed outbound TCP `22`, `8443`, `30080` blocked, while `80`, `443`, `8080` succeeded.
- Authored [docs/ARCHITECTURE.md](ARCHITECTURE.md) with Mermaid diagrams and `ap-south-1` Free-Plan-compliant cost estimate.

### Phase 3 — AWS Infrastructure with Terraform
- Authored [terraform/providers.tf](../terraform/providers.tf), [terraform/variables.tf](../terraform/variables.tf), [terraform/main.tf](../terraform/main.tf), [terraform/outputs.tf](../terraform/outputs.tf), and [terraform/terraform.tfvars.example](../terraform/terraform.tfvars.example).
- Dynamically queried latest Ubuntu 24.04 LTS AMI in `ap-south-1`: `ami-09d8c1e69d114dbf7` (`ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-20261108`).
- Provisioned:
  - EC2 instance `i-07f04268b828911fc` (`c7i-flex.large`, 2 vCPU, 4 GiB RAM, `ap-south-1a`, Public IP `43.204.37.176`, 30 GiB encrypted `gp3` volume).
  - IAM role `vle8-blue-green-ec2-ssm-role` + instance profile `vle8-blue-green-ec2-ssm-profile` with `AmazonSSMManagedInstanceCore`.
  - Key pair `vle8-blue-green-key` (private key stored locally in gitignored `.keys/` and WSL `~/.ssh/vle8-ed25519`).
  - Security Group `sg-091fad6f971b3c43e` (`vle8-blue-green-sg`): TCP `22` closed; TCP `80` allowed only from authorized client `/32` CIDRs; TCP `8080` allowed only from authorized client `/32` CIDRs and the 7 official GitHub Webhook IPv4 CIDRs.
- Verified SSM `PingStatus: Online` (`AgentVersion 3.3.4793.0`) and `ansible all -m ping` via SSM `ProxyCommand`.
- Evidence saved: [evidence/phase3_terraform_outputs.txt](../evidence/phase3_terraform_outputs.txt).

### Phase 4 — Server Configuration with Ansible
- Executed [ansible/jenkins_setup.yml](../ansible/jenkins_setup.yml) over SSM (`ok=46, changed=17, unreachable=0, failed=0, skipped=1`):
  - Configured 2 GiB `/swapfile` with `vm.swappiness=10`.
  - Installed OpenJDK `21.0.13.0.3`, Jenkins LTS `2.580.2` (`-Xms256m -Xmx768m`), Docker CE `29.9.3`, `kubectl v1.32.13`, Minikube `v1.37.0` (`containerd://2.3.4`, IP `192.168.49.2`), and Nginx.
  - Added `ubuntu` and `jenkins` users to the `docker` group and provisioned flattened kubeconfig at `/var/lib/jenkins/.kube/config` (`0600`).
  - Installed `/usr/local/bin/vle8-resume.sh` and `vle8-minikube-resume.service` for automatic Minikube + Nginx proxy recovery after EC2 stop/start.
- Evidence saved: [evidence/phase4_ansible_verification.txt](../evidence/phase4_ansible_verification.txt).

### Phase 5 — Parameterized Web App & Docker Images
- Authored [app/index.html.template](../app/index.html.template), [app/nginx.conf.template](../app/nginx.conf.template), [app/docker-entrypoint-render.sh](../app/docker-entrypoint-render.sh), and [docker/Dockerfile](../docker/Dockerfile) based on `nginx:1.27-alpine`.
- Enforced `Cache-Control: no-store, no-cache, must-revalidate` so browser reloads reflect traffic switches immediately without stale HTML caching.
- Built and container-smoke-tested `myapp:v1` (`BLUE / v1`) and `myapp:v2` (`GREEN / v2`), then loaded both images into Minikube `containerd` (`20.0 MiB` each).
- Evidence saved: [evidence/phase5_docker_build_and_test.txt](../evidence/phase5_docker_build_and_test.txt).

### Phase 6 — Kubernetes Blue & Green Deployments
- Created [kubernetes/namespace.yaml](../kubernetes/namespace.yaml) (`vle8-app`), [kubernetes/deployment-blue.yaml](../kubernetes/deployment-blue.yaml) (`2` replicas, `myapp:v1`), [kubernetes/deployment-green.yaml](../kubernetes/deployment-green.yaml) (`2` replicas, `myapp:v2`), and [kubernetes/service.yaml](../kubernetes/service.yaml) (`NodePort 30080`, initial selector `app=myapp, color=blue`).
- Verified both deployments ran `2/2 Ready` simultaneously (`myapp-blue` pods `10.244.0.3`, `10.244.0.4`; initial `myapp-green` pods `10.244.0.5`, `10.244.0.6`), external `http://43.204.37.176` routed strictly to `BLUE / v1`, and `scripts/verify-green-independent.sh` verified `GREEN / v2` via `kubectl port-forward` with zero production traffic sent to Green.
- Evidence saved: [evidence/phase6_kubernetes_verification.txt](../evidence/phase6_kubernetes_verification.txt), [evidence/screenshot_blue_initial.png](../evidence/screenshot_blue_initial.png).

### Phase 7 & Phase 8 — Jenkins Pipeline & GitHub Webhook Integration
- Created new GitHub repository `https://github.com/Ajay73588/vle8-blue-green-deployment`.
- Configured Jenkins administrator `vle8admin` (stored locally in gitignored `.keys/jenkins_admin.txt`), credential `vle8-deploy-env`, pipeline job `vle8-blue-green-pipeline` reading [jenkins/Jenkinsfile](../jenkins/Jenkinsfile), and plugins (`workflow-aggregator`, `git`, `github`, `credentials-binding`, `timestamper`, `ws-cleanup`, plus `pipeline-stage-view` for Stage View UI and `/wfapi/` REST endpoints).
- Registered GitHub Webhook ID `710369768` (`http://43.204.37.176:8080/github-webhook/`, `application/json`, `push`, active).
- Verified webhook deliveries (`ping` `200 OK` and three real `push` deliveries all returning `200 OK`, triggering Builds `#1`, `#2`, and `#3`).
- Build `#3` (triggered automatically by push commit `e1fa4fc`, ID `3853450446066688000`) built immutable tag `myapp:v2-b3`, smoke-tested it, rolled out `myapp-green` (`10.244.0.9`, `10.244.0.10`), independently tested Green via `port-forward`, and paused cleanly at **Stage 8: Manual Approval** (`"Switch production traffic to GREEN?"`) while production still served `BLUE / v1`.
- Evidence saved: [evidence/phase8_github_webhook.txt](../evidence/phase8_github_webhook.txt), [evidence/phase7_jenkins_build3_console.txt](../evidence/phase7_jenkins_build3_console.txt), [evidence/screenshot_jenkins_stage_view_paused.png](../evidence/screenshot_jenkins_stage_view_paused.png), [evidence/screenshot_jenkins_manual_approval.png](../evidence/screenshot_jenkins_manual_approval.png), [evidence/screenshot_jenkins_pipeline_success.png](../evidence/screenshot_jenkins_pipeline_success.png).

### Phase 9 — Traffic Switching & Rollback Verification
1. **Pre-Switch State (While Build #3 Paused at Stage 8):**
   - `myapp-service` selector: `{"app":"myapp","color":"blue"}`; endpoints: `10.244.0.3:80,10.244.0.4:80`.
   - `http://43.204.37.176/health` returned `BLUE / v1`, while `scripts/verify-green-independent.sh` confirmed `GREEN / v2` (`build: v2-b3`) via `port-forward`.
   - Evidence: [evidence/phase9_pre_switch_verification.txt](../evidence/phase9_pre_switch_verification.txt).
2. **Switch Blue -> Green (After Approving Stage 8):**
   - Jenkins Stages 9–11 patched `myapp-service` selector to `app=myapp,color=green`, endpoints immediately became `10.244.0.10:80,10.244.0.9:80`, and repeated requests to `http://43.204.37.176/health` & `/api/info` returned **`GREEN / v2`** across both Green pods (`myapp-green-5b5cbd6954-jr572` and `myapp-green-5b5cbd6954-jxth2`).
   - Evidence: [evidence/phase9_green_switch_verification.txt](../evidence/phase9_green_switch_verification.txt), [evidence/screenshot_green_live.png](../evidence/screenshot_green_live.png).
3. **Rollback Green -> Blue (Final Demo State):**
   - Executed [scripts/switch-to-blue.sh](../scripts/switch-to-blue.sh) and [scripts/verify-deployment.sh](../scripts/verify-deployment.sh) (`BLUE`, `v1`).
   - `myapp-service` selector reverted to `app=myapp,color=blue` with endpoints `10.244.0.3:80,10.244.0.4:80`, and `http://43.204.37.176/health` + browser immediately returned **`BLUE / v1`**.
   - Both `myapp-blue` (`2/2`) and `myapp-green` (`2/2`) remain healthy (`0` restarts) ready for faculty demonstration.
   - Evidence: [evidence/phase9_rollback_and_health.txt](../evidence/phase9_rollback_and_health.txt), [evidence/screenshot_blue_rollback.png](../evidence/screenshot_blue_rollback.png).

---

## 3. Issues Encountered & Fixes Applied

| # | Issue | Root Cause | Resolution |
|---|---|---|---|
| 1 | `t3a.medium` rejected on `terraform apply` | AWS Free Plan account enforces `free-tier-eligible=true` on EC2 instance launch | Selected Free-Tier-eligible `c7i-flex.large` (2 vCPU, 4 GiB RAM) after pricing check and user approval |
| 2 | Ansible SSH over SSM failed initially | Quoted executable path with spaces in `ProxyCommand` inside `inventory.ini` | Created wrapper [ansible/ssm-proxy.sh](../ansible/ssm-proxy.sh) and referenced `ProxyCommand="/bin/bash ./ssm-proxy.sh %h %p"` |
| 3 | Ansible ignored local `ansible.cfg` in WSL | WSL mounts Windows drives (`/mnt/c`) world-writable (`0777`), causing Ansible to ignore CWD `ansible.cfg` | Exported `ANSIBLE_CONFIG=./ansible.cfg` when invoking `ansible`/`ansible-playbook` |
| 4 | Minikube image loading as `jenkins` user | `jenkins` user could not read `/home/ubuntu/.minikube`; cluster uses `containerd` inside `minikube` container | Added `containerd` fallback (`docker save | docker exec -i minikube ctr -n k8s.io images import -`) in [scripts/load-image-minikube.sh](../scripts/load-image-minikube.sh) |
| 5 | Jenkins Build #1 failed in Stage 2 (`set: Illegal option -o pipefail`) | Jenkins `sh` defaults to `/bin/sh` (`dash`), which does not support `pipefail` | Added `#!/usr/bin/env bash` shebang to every `sh` block in [jenkins/Jenkinsfile](../jenkins/Jenkinsfile) |
| 6 | Jenkins Build #2 failed in Stage 7 (`/tmp/vle8-green-pf.log: Permission denied`) | Earlier test as `ubuntu` left `/tmp/vle8-green-pf.log` owned by `ubuntu`; Ubuntu `fs.protected_regular=2` blocked `jenkins` from truncating it | Updated [scripts/verify-green-independent.sh](../scripts/verify-green-independent.sh) to allocate a unique `mktemp` logfile and clean it up in `trap EXIT` |
| 7 | Headless browser screenshots on Windows failed initially (`ERR_BLOCKED_BY_CLIENT`) | Edge renderer failed in sandbox and Chrome HTTPS-First mode blocked plain HTTP | Used `chrome.exe --headless=new --disable-features=HttpsFirstBalancedModeAutoEnable,HttpsUpgrades` with CDP for Jenkins login & live screenshots |

---

## 4. EC2 Resource & Service Health Monitoring (Verified Post-Rollback)

Captured in [evidence/phase9_rollback_and_health.txt](../evidence/phase9_rollback_and_health.txt):
- **Load Average:** `0.90, 0.80, 0.54` (`up 4:53`)
- **Memory (`free -m`):** `1757 MiB` used / `3812 MiB` total (`2054 MiB` available; `0 MiB` swap used out of `2047 MiB` configured)
- **Root EBS (`df -h /`):** `9.5 GiB` used / `29 GiB` total (`34%` used, `19 GiB` free)
- **Systemd Services:** `jenkins=active`, `docker=active`, `nginx=active`, `vle8-minikube-resume=enabled`
- **Minikube:** `host: Running`, `kubelet: Running`, `apiserver: Running`, `kubectl get nodes`: `minikube Ready v1.37.0`
- **Kubernetes Workloads (`vle8-app`):** `myapp-blue 2/2 Running (0 restarts)`, `myapp-green 2/2 Running (0 restarts)`

---

## 5. Acceptance Test Results (13 Core Tests)

| Test | Scenario | Expected Result | Result | Evidence |
|---|---|---|---|---|
| Test 1 | Workstation & Network Diagnosis | Detect blocked/allowed ports and valid AWS/GitHub/tool access | **PASS** | Phase 1 diagnostics (`VLE8_PROGRESS.md`, `ARCHITECTURE.md`) |
| Test 2 | Terraform Plan & Apply | Valid AWS EC2/SG/IAM provisioning in `ap-south-1` with port 22 closed | **PASS** | [evidence/phase3_terraform_outputs.txt](../evidence/phase3_terraform_outputs.txt) |
| Test 3 | SSM Connectivity | Secure shell/Ansible access over HTTPS 443 via SSM | **PASS** | `aws ssm` Online + Ansible `pong` ([phase4](../evidence/phase4_ansible_verification.txt)) |
| Test 4 | Ansible Configuration | Idempotent install of Java, Jenkins, Docker, kubectl, Minikube, Nginx | **PASS** | [evidence/phase4_ansible_verification.txt](../evidence/phase4_ansible_verification.txt) (`failed=0`) |
| Test 5 | Docker Image Build & Test | Distinct `myapp:v1` (BLUE) & `myapp:v2` (GREEN) pass `/health` smoke checks | **PASS** | [evidence/phase5_docker_build_and_test.txt](../evidence/phase5_docker_build_and_test.txt) |
| Test 6 | Kubernetes Parallel Deploy | `myapp-blue` (2/2) & `myapp-green` (2/2) Running; Service points to Blue | **PASS** | [evidence/phase6_kubernetes_verification.txt](../evidence/phase6_kubernetes_verification.txt) |
| Test 7 | Initial Production Traffic | Public URL returns `BLUE / v1` | **PASS** | [evidence/screenshot_blue_initial.png](../evidence/screenshot_blue_initial.png) |
| Test 8 | Independent Green Verification | `port-forward` hits `GREEN / v2` while production still serves `BLUE / v1` | **PASS** | [evidence/phase9_pre_switch_verification.txt](../evidence/phase9_pre_switch_verification.txt) |
| Test 9 | Jenkins Approval Gate | Build `#3` pauses at `"Switch production traffic to GREEN?"` with prod on Blue | **PASS** | [evidence/screenshot_jenkins_manual_approval.png](../evidence/screenshot_jenkins_manual_approval.png) |
| Test 10 | Blue -> Green Traffic Switch | Approving Stage 8 patches `myapp-service` selector to `color=green` | **PASS** | [evidence/phase7_jenkins_build3_console.txt](../evidence/phase7_jenkins_build3_console.txt) |
| Test 11 | Switched Production Verification | External `http://43.204.37.176` returns `GREEN / v2` across Green pods | **PASS** | [evidence/phase9_green_switch_verification.txt](../evidence/phase9_green_switch_verification.txt), [evidence/screenshot_green_live.png](../evidence/screenshot_green_live.png) |
| Test 12 | Instant Rollback to Blue | `switch-to-blue.sh` patches selector back to `color=blue`; URL returns `BLUE / v1` | **PASS** | [evidence/phase9_rollback_and_health.txt](../evidence/phase9_rollback_and_health.txt), [evidence/screenshot_blue_rollback.png](../evidence/screenshot_blue_rollback.png) |
| Test 13 | GitHub Webhook Auto-Trigger | Push commit triggers webhook `200 OK` and corresponding Jenkins build | **PASS** | [evidence/phase8_github_webhook.txt](../evidence/phase8_github_webhook.txt) |

---

## 6. Final Pre-Completion Verification Checklist

| # | Check Item | Status | Verification Note |
|---|---|---|---|
| 1 | Fresh workspace with no reuse of prior VLE infrastructure | **Verified** | All files, keys, EC2, repo `Ajay73588/vle8-blue-green-deployment`, K8s, Jenkins created from scratch |
| 2 | Environment & college Wi-Fi network diagnosed upfront | **Verified** | Port 22 & 30080 blocked; 80, 443, 8080 open |
| 3 | Ubuntu EC2 provisioned cleanly via Terraform in `ap-south-1` | **Verified** | `i-07f04268b828911fc` (`c7i-flex.large`), `ami-09d8c1e69d114dbf7` |
| 4 | Expected cost calculated & approved prior to apply | **Verified** | `c7i-flex.large` pricing verified & explicitly approved by user |
| 5 | SSH port 22 closed; admin access via SSM Session Manager | **Verified** | SG has no port 22 rule; all automation uses SSM |
| 6 | Inbound 80 & 8080 restricted (no broad admin exposure) | **Verified** | Restricted to user `/32` IPs + official GitHub webhook CIDRs |
| 7 | Ansible configured Java, Jenkins, Docker, kubectl, Minikube, Nginx | **Verified** | Clean playbook run + systemd resume unit verified |
| 8 | Docker images built cleanly with explicit tags (`v1`, `v2`, `v2-b3`) | **Verified** | Smoke-tested & imported into Minikube `containerd` |
| 9 | `myapp-blue` (`v1`) & `myapp-green` (`v2`) run 2 replicas each | **Verified** | 4 pods Running (`2/2` each, `0` restarts) |
| 10 | `myapp-service` initially selects Blue (`color=blue`) | **Verified** | Confirmed before and during Stage 8 pause |
| 11 | External app URL returns `BLUE / v1` initially | **Verified** | Confirmed via HTTP and Chrome screenshot |
| 12 | Green tested independently via `port-forward` before switch | **Verified** | `scripts/verify-green-independent.sh` passed with Blue live |
| 13 | Jenkins builds, smoke-tests, deploys Green, waits for approval | **Verified** | Build `#3` Stages 1–8 verified |
| 14 | Manual approval gate halts switch until approved | **Verified** | Build `#3` held `PAUSED_PENDING_INPUT` until explicit POST approval |
| 15 | Approving switches `myapp-service` selector from `blue` to `green` | **Verified** | Selector & endpoints updated to `10.244.0.9:80`, `10.244.0.10:80` |
| 16 | External app URL returns `GREEN / v2` after switch | **Verified** | Both Green pods verified + [screenshot_green_live.png](../evidence/screenshot_green_live.png) |
| 17 | Rollback switches selector back to `blue` & restores `BLUE / v1` | **Verified** | Verified via [switch-to-blue.sh](../scripts/switch-to-blue.sh) + [screenshot_blue_rollback.png](../evidence/screenshot_blue_rollback.png) |
| 18 | New GitHub repo connected with active verified webhook | **Verified** | Webhook `710369768` delivered 4/4 `200 OK` events triggering Builds `#1–#3` |
| 19 | Blue left as active final state for faculty demonstration | **Verified** | `myapp-service` points to `color=blue` (`BLUE / v1`) |
| 20 | Genuine outputs & screenshots stored in `evidence/` | **Verified** | 9 text logs + 6 visually inspected PNG screenshots |
| 21 | No secrets/keys/tokens committed or exposed | **Verified** | `.keys/`, `terraform.tfvars`, and `.tfstate` excluded via `.gitignore` |

---

## 7. Known Limitations & Operational Considerations

1. **Dynamic College/Client Public IP:** When switching to a different Wi-Fi/campus network during faculty demo, add the new public IP `/32` to `terraform/terraform.tfvars` (`allowed_client_cidrs`) and run `terraform apply` so ports `80` and `8080` remain reachable.
2. **HTTP Endpoints in Demo Lab:** Jenkins (`:8080`) and Nginx (`:80`) use HTTP rather than TLS because there is no public domain name attached to the lab EC2 EIP; do not expose real credentials over untrusted networks, and rotate the Jenkins password or tear down infrastructure after the faculty evaluation.
3. **Ephemeral Public IP on EC2 Stop/Start:** Stopping (`aws ec2 stop-instances`) and later starting (`aws ec2 start-instances`) the EC2 instance without an Elastic IP changes its public IPv4 address. If restarted later, update the GitHub Webhook URL (`http://<NEW_IP>:8080/github-webhook/`) in GitHub repo settings. (`vle8-minikube-resume.service` automatically restarts Minikube and updates Nginx's upstream Minikube IP.)
4. **In-Flight Keep-Alive Connections:** Patching `myapp-service` updates `kube-proxy` rules for new connections immediately, while any pre-existing HTTP keep-alive TCP connections may complete their current request on the previous backend pod before closing/reconnecting.
