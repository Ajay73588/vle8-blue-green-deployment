# VLE-8 Progress Tracker

**Project:** VLE-8 — Blue-Green Deployment using DevOps Tools  
**Workspace:** `c:\Users\LENOVO\Downloads\vle 8`  
**AWS Region:** `ap-south-1` (Mumbai)  
**EC2 Instance:** `i-07f04268b828911fc` (`c7i-flex.large`, Public IP `43.204.37.176`)  
**GitHub Repository:** `https://github.com/Ajay73588/vle8-blue-green-deployment`

## Phase Status

| Phase | Description | Status | Notes |
|---|---|---|---|
| Phase 1 | Inspect environment, network, AWS access, workspace | **Completed** | Outbound `:22`, `:8443`, `:30080` blocked on college Wi-Fi; `:80`, `:443`, `:8080` open. |
| Phase 2 | Design architecture and estimate AWS cost | **Completed** | SSM Session Manager + Nginx `:80` -> Minikube `:30080`. |
| Phase 3 | Provision AWS infrastructure via Terraform | **Completed** | `c7i-flex.large` (`i-07f04268b828911fc`, `43.204.37.176`) provisioned; SG updated for current IP `59.152.80.69/32` + college IP `103.4.222.252/32` + GitHub webhook CIDRs. |
| Phase 4 | Configure Ubuntu with Ansible | **Completed** | Java 21, Jenkins 2.580.2, Docker 29.9.3, kubectl v1.32.13, Minikube v1.37.0 (containerd), Nginx, and auto-resume systemd service verified. |
| Phase 5 | Build demonstration app and Docker images | **Completed** | Built & smoke-tested `myapp:v1` (BLUE) and `myapp:v2` (GREEN), loaded both into Minikube containerd. |
| Phase 6 | Configure Kubernetes Blue and Green environments | **Completed** | `myapp-blue` (2/2) and `myapp-green` (2/2) running simultaneously; `myapp-service` routes to Blue (`BLUE / v1`); Green verified independently via port-forward. |
| Phase 7 | Configure Jenkins CI/CD pipeline | **Completed** | Installed plugins (`workflow-aggregator`, `git`, `github`, `credentials-binding`, `timestamper`, `ws-cleanup`), configured `vle8admin`, created credential `vle8-deploy-env`, and configured `vle8-blue-green-pipeline`. |
| Phase 8 | GitHub repository & webhook integration | **In Progress** | Created `Ajay73588/vle8-blue-green-deployment`, pushed initial commit, created GitHub Webhook (ID `710369768`, ping `200 OK`); triggering push delivery test now. |
| Phase 9 | Execute Blue-Green switching and rollback | Pending | Will run end-to-end Jenkins pipeline + manual approval + switch + rollback. |
| Phase 10 | Documentation, evidence, faculty demo & viva prep | Pending | Finalizing test results, genuine screenshots, and `docs/IMPLEMENTATION.md`. |

## Current Blockers
- Fixing headless Edge screenshot flag so genuine PNG screenshots can be captured cleanly.
