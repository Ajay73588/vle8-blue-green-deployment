# VLE-8 Faculty Demonstration Guide, Checklist & Viva Q&A

**Project:** VLE-8 — Blue-Green Deployment using DevOps Tools  
**AWS Instance:** `i-07f04268b828911fc` (`c7i-flex.large`, `ap-south-1` Mumbai)  
**EC2 Public IP:** `43.204.37.176`  
**Application URL:** `http://43.204.37.176`  
**Jenkins URL:** `http://43.204.37.176:8080`  
**Kubernetes Namespace:** `vle8-app`

---

## 1. Concise Project Explanation (2-Minute Faculty Pitch)

> "In Virtual Lab Experiment 8, we implemented an automated **Blue-Green Deployment** pipeline using Terraform, Ansible, GitHub, Jenkins, Docker, and Kubernetes on AWS (`ap-south-1`).
>
> Instead of updating live containers in place—which risks downtime or broken releases—we run **two identical Kubernetes Deployments** inside Minikube: **`myapp-blue` (`v1`, 2 replicas)** and **`myapp-green` (`v2`, 2 replicas)**. Initially, the Kubernetes Service `myapp-service` uses label selector `app=myapp, color=blue`, so all live user traffic goes to Blue.
>
> When new code is pushed to GitHub, a webhook triggers our **Jenkins pipeline**, which validates the code and Kubernetes manifests, builds and smoke-tests the new **`myapp:v2`** Docker image, loads it into Minikube, deploys `myapp-green`, verifies Green Pods independently via `kubectl port-forward` **without sending production traffic to it**, and pauses at a **Manual Approval gate**. Once approved, Jenkins patches `myapp-service`'s selector from `color=blue` to `color=green`, shifting live traffic instantaneously to Green `v2`. If any issue appears, a single `kubectl patch` rolls traffic back to `color=blue` (`v1`) in under a second."

---

## 2. Pre-Demo Checklist (Before Entering Viva / Lab)

- [ ] Verify current laptop public IP (`curl.exe -s https://checkip.amazonaws.com`); if on a different Wi-Fi/hotspot, update `terraform/terraform.tfvars` and run `terraform apply` so ports `80` and `8080` allow your new IP.
- [ ] Verify EC2 instance is `running` and SSM `Online`.
- [ ] Open two browser tabs:
  - Tab 1: `http://43.204.37.176` (Live App — should initially show **BLUE / v1**)
  - Tab 2: `http://43.204.37.176:8080` (Jenkins UI)
- [ ] Open an AWS SSM shell to the EC2 server in PowerShell:
  ```powershell
  aws ssm start-session --region ap-south-1 --target i-07f04268b828911fc
  ```
  Then switch to `ubuntu` user in the SSM shell:
  ```bash
  sudo su - ubuntu
  ```

---

## 3. Live 12-Step Faculty Demonstration Sequence

### Step 1 — Explain Architecture
Show [ARCHITECTURE.md](../docs/ARCHITECTURE.md) diagram: `Developer -> GitHub -> Jenkins -> Docker -> Minikube (Blue v1 + Green v2) -> Service Switch -> Nginx (:80)`.

### Step 2 — Show GitHub Repository
Open the new VLE-8 GitHub repository in the browser and highlight `app/`, `docker/Dockerfile`, `terraform/`, `ansible/`, `kubernetes/`, and `jenkins/Jenkinsfile`.

### Step 3 — Show Jenkins Pipeline
Open `http://43.204.37.176:8080` and show the `vle8-blue-green-pipeline` job and its 11-stage `Jenkinsfile`.

### Step 4 — Show Blue Running as Current Live Version
Open `http://43.204.37.176` in browser (BLUE theme, `v1`) and verify in **EC2 SSM terminal**:
```bash
curl -s http://127.0.0.1/api/info | jq .
```

### Step 5 — Show Both Blue and Green Pods Running Simultaneously in Kubernetes
Run in **EC2 SSM terminal**:
```bash
kubectl get deployments,pods,svc,endpoints -n vle8-app -o wide
kubectl get service myapp-service -n vle8-app -o jsonpath='{.spec.selector}'; echo
```
Point out `myapp-blue` (2/2 Ready) and `myapp-green` (2/2 Ready) running side-by-side while `myapp-service` endpoints match **only** the 2 Blue Pod IPs.

### Step 6 — Trigger Jenkins Pipeline
Click **Build Now** in Jenkins (or push a small commit to GitHub to show webhook auto-triggering).

### Step 7 — Show Green Build & Independent Verification
Show Jenkins console stages `3` through `7`:
- Builds explicit immutable tag `myapp:v2-b<BUILD_NUMBER>`
- Smoke-tests container `/health`
- Rolls out `myapp-green`
- Verifies Green independently via `kubectl port-forward` while `myapp-service` still routes to Blue.

### Step 8 — Show Manual Approval Gate
Point out Jenkins pausing at Stage `8. Manual Approval`: `"Switch production traffic to GREEN?"` while `http://43.204.37.176` STILL displays **BLUE / v1**.

### Step 9 — Approve Traffic Switch
Click **Switch to GREEN** in Jenkins.

### Step 10 — Refresh Application & Show GREEN / v2
Refresh `http://43.204.37.176` in browser — UI immediately turns **GREEN (`v2`)**! Confirm in **EC2 SSM terminal**:
```bash
kubectl get service myapp-service -n vle8-app -o jsonpath='{.spec.selector}'; echo
kubectl get endpoints myapp-service -n vle8-app
curl -s http://127.0.0.1/health
```

### Step 11 — Demonstrate Rollback
Run in **EC2 SSM terminal**:
```bash
kubectl patch service myapp-service -n vle8-app -p '{"spec":{"selector":{"app":"myapp","color":"blue"}}}'
```
(Or run `bash ~/vle8-repo/scripts/switch-to-blue.sh`).

### Step 12 — Refresh Application & Show BLUE / v1
Refresh `http://43.204.37.176` — UI instantaneously returns to **BLUE (`v1`)**!

---

## 4. Likely Viva Questions & Model Answers

1. **What is Blue-Green Deployment and why is it used?**
   It is a release strategy that runs two identical production environments (**Blue** and **Green**). Only one receives live user traffic at a time (`Blue`). The new version (`Green`) is deployed and verified in parallel without impacting users, then traffic is switched instantaneously at the router/Service layer, enabling near-zero downtime and instant rollback.

2. **How does Kubernetes switch traffic between Blue and Green without restarting pods?**
   A Kubernetes `Service` (`myapp-service`) matches Pods using `spec.selector` labels (`app: myapp`, `color: blue`). Patching `spec.selector.color` from `blue` to `green` updates the Service's `Endpoints`/`EndpointSlice` immediately, and `kube-proxy` updates node iptables/IPVS rules to route new connections to Green Pods.

3. **Why do both Deployments (`myapp-blue` and `myapp-green`) have readiness probes?**
   Without `readinessProbe`, Kubernetes would route traffic to a newly started Pod as soon as its container process begins, even before Nginx is listening. Readiness probes ensure Pods only enter Service endpoints once `/health` returns HTTP `200`.

4. **How did you test the Green environment before sending production traffic to it?**
   During Jenkins Stage 7, `scripts/verify-green-independent.sh` opens a temporary `kubectl port-forward` directly to `deployment/myapp-green` and verifies HTTP `200` on `/health` (`color: GREEN`, `version: v2`), leaving `myapp-service` pointing to `color: blue` until manual approval.

5. **How is rollback achieved if Green v2 has a bug in production?**
   Because `myapp-blue` (`v1`) stays running and warm with 2 healthy replicas, rollback simply patches `myapp-service` selector back to `color: blue`, restoring `v1` immediately without rebuilding or redeploying containers.

6. **Why did you avoid `latest` Docker tags?**
   `latest` is mutable and ambiguous—Kubernetes with `imagePullPolicy: IfNotPresent` won't re-pull or detect a new build if the tag string didn't change. Using explicit immutable tags (`v1`, `v2-b<BUILD_NUMBER>`) guarantees traceability and forces Kubernetes to roll out the exact new image.

7. **Why use Terraform AND Ansible instead of just one tool?**
   Terraform handles **infrastructure provisioning** declaratively (AWS EC2, IAM role, Security Group, EBS volume, state tracking), whereas Ansible handles **OS configuration management** idempotently (installing Java, Docker, Jenkins, kubectl, Minikube, Nginx, and service tuning).

8. **How did you connect securely when college Wi-Fi blocked outbound SSH port 22?**
   We kept TCP `22` closed in the AWS Security Group and attached the `AmazonSSMManagedInstanceCore` IAM role to EC2. All shell access and Ansible runs use **AWS Systems Manager Session Manager (`ProxyCommand` via `AWS-StartSSHSession`)** encapsulated over outbound HTTPS port `443`.

9. **Why did you put Nginx in front of Minikube NodePort?**
   Minikube's NodePort (`30080`) was both internal to the Minikube Docker network and blocked outbound on campus Wi-Fi (`30080`). Nginx on the EC2 host listens on standard HTTP port `80` and proxies to `<minikube-ip>:30080`, preserving Kubernetes Blue-Green routing while making the app accessible at `http://<EC2_PUBLIC_IP>`.

10. **What is a limitation of Blue-Green deployment?**
    It temporarily doubles compute/memory resource usage (running both Blue and Green replicas simultaneously), and stateful database schema changes must be backward-compatible so both versions can coexist safely during switch and rollback.

