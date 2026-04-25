# Phase 0 — The Foundation

## Time: ~10-12 hours across Week 1 | Budget: ~$2-5 (state bucket + API calls only)

---

## Why This Phase Exists (Read This First)

Every enterprise outage post-mortem you'll ever read has one thing in common: **someone changed something, and nobody knows what, when, or why.**

Phase 0 exists to make that sentence impossible. By the end of this phase, every piece of infrastructure you build will be:

- **Versioned** — stored in Git, reviewable, rollbackable
- **Automated** — no human clicks in the GCP console after setup
- **Auditable** — every change has a PR, an approval, a record
- **Destroyable** — you can tear everything down in one command and rebuild it identically

This isn't just "best practice." In fintech, regulators (RBI, SOC 2 auditors, PCI assessors) **require** this. They will ask: "Show me the audit trail for every infrastructure change in the last 90 days." If your answer is "we clicked buttons in the console," you fail the audit.

**The business problem this solves:** "We don't know what's in production, who put it there, or how to rebuild it if it dies."

---

## Session 1: GCP Project Setup & Billing Protection (~2 hours)

### Why a Dedicated Project?

In enterprise, every product/team gets its own GCP project. This isn't organizational OCD — it's a **blast radius boundary**. If someone misconfigures IAM in Project A, Project B is untouched. It's also how you track costs per team/product.

You're doing the same thing. One project. One purpose. Clean boundaries.

### Step-by-Step

#### 1.1 Create the GCP Project

```bash
# Install gcloud CLI if you haven't
# https://cloud.google.com/sdk/docs/install

# Login
gcloud auth login

# Create a new project (pick a globally unique ID)
# Convention: {company}-{environment}-{purpose}
# For you: learning project, so:
gcloud projects create fintech-platform-lab --name="Fintech Platform Lab"

# Set it as your active project
gcloud config set project fintech-platform-lab

# Link your billing account
# First, find your billing account ID:
gcloud billing accounts list

# Then link it:
gcloud billing projects link fintech-platform-lab \
  --billing-account=01B4D0-D03294-BA2BBB
```

> **Why the naming convention?** In enterprise, you'll see hundreds of projects.
> `acme-prod-payments` vs `my-project-123` — which one do you understand at 3 AM during an outage?

#### 1.2 Set Billing Alerts (DO THIS NOW, NOT LATER)

This is the single most important thing you'll do today.

Go to: **GCP Console → Billing → Budgets & Alerts**

Create 3 alerts:

| Alert | Amount | Why |
|-------|--------|-----|
| Warning | $50 | "I'm spending faster than planned" |
| Serious | $100 | "Something is wrong, investigate NOW" |
| Critical | $200 | "Stop everything, destroy resources" |

Set notification to your email for ALL thresholds (50%, 90%, 100%).

```bash
# You can also do this via CLI, but console is fine for this one-time setup.
# In enterprise, even billing alerts are in Terraform. You'll add that later.
```

> **War story:** Engineers lose their free credits in 5-7 days, not 90 days.
> The #1 cause: a GKE cluster left running over a weekend.
> The #2 cause: a NAT gateway or load balancer they forgot about.
> The #3 cause: persistent disks that survive `terraform destroy`.

#### 1.3 Enable Required APIs

GCP APIs are disabled by default. This is a security feature — you can't accidentally use (and get billed for) services you haven't explicitly enabled.

```bash
# Core APIs we'll need across all phases
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbilling.googleapis.com \
  serviceusage.googleapis.com \
  storage.googleapis.com
```

> **Why not enable everything?** Principle of least privilege applies to APIs too.
> Every enabled API is an attack surface. Fintech auditors check this.

#### 1.4 Create a Terraform State Bucket

**Why remote state matters — feel the pain first:**

Terraform tracks what it's built in a "state file." By default, this file sits on your laptop. What happens when:
- Your laptop dies? → You can't manage your infrastructure anymore.
- Two people run `terraform apply` simultaneously? → State corruption. Resources get orphaned.
- An auditor asks "what's deployed right now?" → You email around a JSON file?

Remote state in GCS fixes all three: durable, lockable, auditable.

```bash
# Create the bucket (name must be globally unique)
gsutil mb -p fintech-platform-lab `
  -l asia-south1 `
  -b on `
  gs://fintech-platform-lab-tf-state

# Enable versioning — so you can recover from state corruption
gsutil versioning set on gs://fintech-platform-lab-tf-state
```

> **Why asia-south1?** You're in Hyderabad. Keep state close to you.
> In real enterprise, state is in the same region as the resources it manages.
> **Why versioning?** Because `terraform state` corruption is a real thing,
> and the fix is "restore the previous version." Without versioning, you're rebuilding from scratch.

---

## Session 2: Terraform + Terragrunt Skeleton (~3 hours)

### Why Terraform? Why Not Pulumi/CDK/CloudFormation?

Quick honest comparison:

| Tool | Pros | Cons | Why (not) for you |
|------|------|------|-------------------|
| **Terraform** | Industry standard, massive community, every job listing asks for it, multi-cloud | HCL is limited, state management complexity | ✅ Use this. 90% of DevOps jobs require it |
| Pulumi | Real programming languages (Python, Go, TS), better testing | Smaller community, fewer modules, some jobs don't know it | Skip for now. Learn after Terraform. |
| CDK/CFN | Native AWS, no state file | AWS-only, verbose, slow | You're on GCP. Irrelevant. |
| Crossplane | K8s-native, GitOps-friendly | Complex, early ecosystem | Phase 2+ consideration, not now |

### Why Terragrunt?

Terraform alone gets messy fast. You end up copy-pasting the same backend config, provider config, and variable values across 15 folders. Terragrunt is a thin wrapper that keeps things DRY.

**The pain without Terragrunt:** You have `dev/main.tf`, `staging/main.tf`, `prod/main.tf` — all with identical backend blocks and 80% identical variables. You change a module version in dev, forget to change it in prod. Outage.

**With Terragrunt:** One `terragrunt.hcl` at the root defines the backend. Child configs inherit it. Change once, applies everywhere.

### The Folder Structure

```
infrastructure/
├── terragrunt.hcl                    # Root config: backend, provider defaults
├── environments/
│   ├── dev/
│   │   ├── terragrunt.hcl            # Dev-specific variables (small instances, 1 node)
│   │   ├── gke/
│   │   │   └── terragrunt.hcl        # GKE cluster config for dev
│   │   ├── networking/
│   │   │   └── terragrunt.hcl        # VPC, subnets for dev
│   │   └── iam/
│   │       └── terragrunt.hcl        # Service accounts, roles for dev
│   └── prod/
│       ├── terragrunt.hcl            # Prod-specific variables (bigger instances, HA)
│       ├── gke/
│       │   └── terragrunt.hcl
│       ├── networking/
│       │   └── terragrunt.hcl
│       └── iam/
│           └── terragrunt.hcl
└── modules/
    ├── gke-cluster/                   # Reusable module: creates a GKE cluster
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── networking/                    # Reusable module: VPC + subnets + firewall
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── iam/                           # Reusable module: service accounts + bindings
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

> **Why this structure?**
> - `modules/` = reusable blueprints. Like functions in code. Write once, call many times.
> - `environments/` = specific deployments. Dev uses the same module as prod, but with different inputs.
> - This is the structure used by Hashicorp's own recommendations and most enterprise teams.

### Create the Root Terragrunt Config

Create `infrastructure/terragrunt.hcl`:

```hcl
# Root terragrunt.hcl
# This is inherited by ALL child configs. Change here = change everywhere.

# Remote state configuration
remote_state {
  backend = "gcs"
  config = {
    bucket   = "fintech-platform-lab-tf-state"
    prefix   = "${path_relative_to_include()}/terraform.tfstate"
    project  = "fintech-platform-lab"
    location = "asia-south1"
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# Generate provider config for all children
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "asia-south1"
}
EOF
}
```

> **What's happening here?**
> - `remote_state` → Every child module stores its state in GCS, in a subfolder matching its path. So `environments/dev/gke/` stores state at `environments/dev/gke/terraform.tfstate`. Clean separation.
> - `generate "provider"` → Every child gets the Google provider configured automatically. No copy-paste.
> - `path_relative_to_include()` → Terragrunt magic. It figures out the child's path relative to this root file and uses it as the state prefix.

### Create the Dev Environment Config

Create `infrastructure/environments/dev/terragrunt.hcl`:

```hcl
# Dev environment root config
# All modules in dev/ inherit these variables

include "root" {
  path = find_in_parent_folders()
}

inputs = {
  project_id  = "fintech-platform-lab"
  region      = "asia-south1"
  environment = "dev"

  # Dev-specific: keep everything small and cheap
  # These values get passed to modules as variables
}
```

### Create the Networking Module

Create `infrastructure/modules/networking/main.tf`:

```hcl
# VPC and Subnets
# Why a custom VPC? The default VPC has overly permissive firewall rules.
# In fintech, the default VPC is a security audit failure.

resource "google_compute_network" "main" {
  name                    = "${var.environment}-vpc"
  auto_create_subnetworks = false  # We control subnets explicitly
  project                 = var.project_id
}

# GKE subnet with secondary ranges for pods and services
resource "google_compute_subnetwork" "gke" {
  name          = "${var.environment}-gke-subnet"
  ip_cidr_range = var.subnet_cidr        # Node IPs
  region        = var.region
  network       = google_compute_network.main.id
  project       = var.project_id

  # Secondary ranges for GKE pods and services
  # Why secondary ranges? GKE uses VPC-native networking.
  # Pods get IPs from a separate range, not the node range.
  # This means pods are directly routable in the VPC — needed for
  # service mesh, network policies, and basically everything enterprise.
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  # Enable private Google access — pods can reach Google APIs
  # without a public IP. Security requirement for fintech.
  private_google_access = true
}

# Cloud NAT — gives private nodes outbound internet access
# without public IPs. Required for pulling container images.
resource "google_compute_router" "router" {
  name    = "${var.environment}-router"
  region  = var.region
  network = google_compute_network.main.id
  project = var.project_id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.environment}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  project                            = var.project_id
  nat_ip_allocate_option            = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  # Logging — you want to see NAT traffic for debugging and auditing
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
```

Create `infrastructure/modules/networking/variables.tf`:

```hcl
variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, staging, prod)"
}

variable "subnet_cidr" {
  type        = string
  description = "CIDR range for the GKE subnet (node IPs)"
  default     = "10.0.0.0/20"  # 4,094 IPs — plenty for dev
}

variable "pods_cidr" {
  type        = string
  description = "Secondary CIDR for GKE pods"
  default     = "10.4.0.0/14"  # 262,142 IPs — K8s is hungry for pod IPs
}

variable "services_cidr" {
  type        = string
  description = "Secondary CIDR for GKE services"
  default     = "10.8.0.0/20"  # 4,094 IPs — enough for services
}
```

Create `infrastructure/modules/networking/outputs.tf`:

```hcl
output "network_id" {
  value = google_compute_network.main.id
}

output "network_name" {
  value = google_compute_network.main.name
}

output "subnet_id" {
  value = google_compute_subnetwork.gke.id
}

output "subnet_name" {
  value = google_compute_subnetwork.gke.name
}
```

### Wire the Dev Networking

Create `infrastructure/environments/dev/networking/terragrunt.hcl`:

```hcl
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../../modules/networking"
}

inputs = {
  project_id  = "fintech-platform-lab"
  region      = "asia-south1"
  environment = "dev"

  # Dev gets smaller CIDR ranges — we don't need 262K pod IPs for learning
  # But we keep the structure identical to prod
  subnet_cidr   = "10.0.0.0/20"
  pods_cidr     = "10.4.0.0/14"
  services_cidr = "10.8.0.0/20"
}
```

---

## Session 3: GitHub Repository & CI (~3 hours)

### Repo Structure

```
fintech-platform/
├── .github/
│   └── workflows/
│       └── terraform-plan.yml        # CI: runs plan on every PR
├── infrastructure/                   # Everything from Session 2
│   ├── terragrunt.hcl
│   ├── environments/
│   └── modules/
├── kubernetes/                       # Will be used in Phase 1+
│   ├── base/                         # Kustomize base manifests
│   └── overlays/
│       ├── dev/
│       └── prod/
├── docs/                             # Architecture Decision Records
│   └── adr/
│       └── 001-why-gke-over-eks.md
├── journal/                          # YOUR LEARNING JOURNAL
│   ├── phase-0.md
│   ├── phase-1.md
│   └── ...
└── README.md
```

### GitHub Actions: Terraform Plan on PR

Create `.github/workflows/terraform-plan.yml`:

```yaml
# Why this workflow exists:
# Every infrastructure change must be reviewed before applying.
# This runs `terraform plan` on PRs so reviewers see exactly what will change.
# In enterprise, this is non-negotiable — no one applies without a reviewed plan.

name: Terraform Plan

on:
  pull_request:
    paths:
      - 'infrastructure/**'

# IMPORTANT: These permissions are needed for Workload Identity Federation
# We're NOT using long-lived service account keys (security anti-pattern)
permissions:
  contents: read
  pull-requests: write
  id-token: write  # Required for OIDC token → Workload Identity

env:
  TG_VERSION: '0.55.0'
  TF_VERSION: '1.7.0'

jobs:
  plan:
    name: Terraform Plan
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: infrastructure/environments/dev

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      # Authenticate to GCP using Workload Identity Federation
      # NO service account keys stored in GitHub Secrets
      # This is the enterprise-grade way to do it
      - name: Authenticate to GCP
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: 'projects/YOUR_PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider'
          service_account: 'terraform-ci@fintech-platform-lab.iam.gserviceaccount.com'

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Setup Terragrunt
        uses: autero1/action-terragrunt@v3
        with:
          terragrunt-version: ${{ env.TG_VERSION }}

      - name: Terragrunt Init
        run: terragrunt run-all init --terragrunt-non-interactive

      - name: Terragrunt Plan
        id: plan
        run: terragrunt run-all plan --terragrunt-non-interactive -no-color 2>&1 | tee plan_output.txt
        continue-on-error: true

      # Post the plan as a PR comment — reviewers see exactly what changes
      - name: Comment Plan on PR
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const plan = fs.readFileSync('infrastructure/environments/dev/plan_output.txt', 'utf8');
            const truncated = plan.length > 60000 ? plan.substring(0, 60000) + '\n\n... truncated ...' : plan;
            
            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body: `## Terraform Plan Results\n\n\`\`\`\n${truncated}\n\`\`\``
            });

      - name: Fail if plan failed
        if: steps.plan.outcome == 'failure'
        run: exit 1
```

### Setting Up Workload Identity Federation (The Enterprise Way)

**Why not just use a service account key?**

Service account keys are long-lived credentials stored in GitHub Secrets. If GitHub gets breached (it has happened), your keys are exposed, and attackers have full access to your GCP project.

Workload Identity Federation uses short-lived, automatically rotating tokens. GitHub proves its identity to GCP via OIDC, GCP issues a temporary token. No secrets stored anywhere.

This is what enterprises and fintechs actually use. It's also what auditors want to see.

```bash
# Create a service account for Terraform CI
gcloud iam service-accounts create terraform-ci \
  --display-name="Terraform CI" \
  --project=fintech-platform-lab

# Grant it the roles it needs (principle of least privilege)
# Editor is too broad for prod, but fine for your learning project
gcloud projects add-iam-policy-binding fintech-platform-lab --member="serviceAccount:terraform-ci@fintech-platform-lab.iam.gserviceaccount.com" --role="roles/editor"

# Also needs to manage IAM (to create service accounts for GKE, etc.)
gcloud projects add-iam-policy-binding fintech-platform-lab --member="serviceAccount:terraform-ci@fintech-platform-lab.iam.gserviceaccount.com" --role="roles/iam.securityAdmin"

# Get your project number (different from project ID)
gcloud projects describe fintech-platform-lab --format="value(projectNumber)"
# Note this number — you'll need it below  483262637629

# Create Workload Identity Pool
gcloud iam workload-identity-pools create "github-pool" --location="global" --display-name="GitHub Actions Pool" --project=fintech-platform-lab

# Create the OIDC provider for GitHub
gcloud iam workload-identity-pools providers create-oidc "github-provider" --location="global" --workload-identity-pool="github-pool" `
  --display-name="GitHub Provider" `
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" `
  --issuer-uri="https://token.actions.githubusercontent.com" `
  --attribute-condition="assertion.repository_owner == 'arunponugoti1'" `
  --project=fintech-platform-lab

# Allow the GitHub repo to impersonate the service account
# REPLACE: your-github-username/fintech-platform with your actual repo
gcloud iam service-accounts add-iam-policy-binding \
  terraform-ci@fintech-platform-lab.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/483262637629/locations/global/workloadIdentityPools/github-pool/attribute.repository/arunponugoti1/fintech-platform" \
  --project=fintech-platform-lab
```

---

## Session 4: Your First Apply + Destroy Cycle (~2 hours)

### The Moment of Truth

```bash
cd infrastructure/environments/dev/networking

# Init — downloads providers, configures backend
terragrunt init

# Plan — shows what will be created (READ THIS CAREFULLY)
terragrunt plan

# Apply — creates the resources
terragrunt apply
```

**What you should see:**
- 1 VPC created
- 1 Subnet with 2 secondary ranges
- 1 Cloud Router
- 1 Cloud NAT

**Go to GCP Console and verify.** Click through VPC Networks, look at the subnet, see the secondary ranges. This is your infrastructure. You defined it in code, and it exists.

### Now Destroy It

```bash
terragrunt destroy
```

**Go to GCP Console and verify it's gone.**

This is the muscle memory you need. Apply → verify → destroy. Every session. The cluster doesn't exist when you're not learning. Your wallet will thank you.

### The Deliberate Break (Do This)

Before you destroy, try this:

1. Go to GCP Console
2. Manually change the subnet's CIDR range via the UI
3. Run `terragrunt plan`

**What happens?** Terraform detects the drift and wants to fix it. This is the entire point of IaC — the code is the source of truth, not the console. When someone clicks a button in production at 2 AM, Terraform catches it.

This is called **drift detection**, and it's why enterprises mandate "no console changes."

---

## Architecture Decision Records (ADR)

Create `docs/adr/001-why-gke-over-eks.md`:

```markdown
# ADR-001: Why GKE as Primary Cloud

## Status: Accepted

## Context
Building a Kubernetes platform for fintech workloads. Need to choose primary cloud provider.

## Decision
GKE on Google Cloud Platform as primary (and for now, only) cloud.

## Reasoning
1. GKE is the most mature managed Kubernetes (Google created K8s)
2. GKE Autopilot reduces node management overhead for a small team
3. $300 free credits available — practical constraint
4. VPC-native networking is default (pod IPs routable in VPC)
5. Workload Identity is native (no need for external tools)
6. Binary Authorization built-in (supply chain security)

## Alternatives Considered
- **EKS (AWS):** Larger market share but K8s integration less native.
  Networking (VPC CNI) has known IP exhaustion issues. More operational overhead.
- **AKS (Azure):** Good K8s support but smaller community.
  Less relevant for target job market in India.
- **Multi-cloud from day 1:** Rejected. Adds 3x complexity with no business justification yet.

## Consequences
- Team needs GCP expertise (not AWS)
- Some tools that are AWS-specific won't work
- Can add AWS as secondary in future phase if business requires it

## Review Date: End of Phase 3
```

> **Why ADRs?** In 6 months, you won't remember why you chose GKE. New team members will ask.
> ADRs are how mature engineering teams preserve decisions. They're also interview gold:
> "We evaluated X, Y, Z and chose X because..." — that's a senior engineer answer.

---

## Journal Entry Template: Phase 0

Create `journal/phase-0.md`:

```markdown
# Phase 0 Journal: The Foundation

## Date Started:
## Date Completed:

## What Broke and Why
<!-- Write every error you hit. The exact error message. What caused it. How you fixed it. -->
<!-- Example: "Terraform init failed with 'Error configuring the backend' because I had a typo in the bucket name" -->

## What I Tried That Didn't Work
<!-- These failed attempts are MORE valuable than successes for interviews -->

## Aha Moments
<!-- The moments where something clicked. Write them immediately. -->
<!-- Example: "I finally understand why remote state exists - it's not about backup, it's about locking" -->

## The Mental Model I Now Have
<!-- In ONE paragraph, no jargon, explain what Terraform + Terragrunt does to someone who doesn't know tech -->
<!-- If you can't explain it simply, you don't understand it yet -->

## Questions I Still Have
<!-- Don't Google these yet. Bring them to Phase 1. Some will answer themselves. -->

## Time Spent
<!-- Track honestly. This helps you estimate future work — a key senior skill -->
- Session 1 (GCP setup): ___ hours
- Session 2 (Terraform skeleton): ___ hours
- Session 3 (GitHub + CI): ___ hours
- Session 4 (Apply/Destroy): ___ hours
- Total: ___ hours
```

---

## Phase 0 Checklist — Don't Move to Phase 1 Until All Are Done

- [ ] GCP project created with billing linked
- [ ] Billing alerts set at $50, $100, $200
- [ ] Required APIs enabled
- [ ] GCS bucket for Terraform state (versioning ON)
- [ ] Terraform + Terragrunt installed locally
- [ ] Folder structure created as described
- [ ] Root `terragrunt.hcl` with remote state config
- [ ] Networking module written (VPC + Subnet + NAT)
- [ ] Dev environment wired to networking module
- [ ] Successfully ran `terragrunt apply` for networking
- [ ] Verified resources in GCP Console
- [ ] Tried the "deliberate drift" exercise
- [ ] Successfully ran `terragrunt destroy`
- [ ] Verified resources are gone in Console
- [ ] GitHub repo created with the full folder structure
- [ ] Workload Identity Federation configured
- [ ] GitHub Actions workflow committed (even if untested — test on first real PR)
- [ ] ADR-001 written
- [ ] Phase 0 journal entry completed (all sections filled)
- [ ] Resources destroyed (CONFIRM your bill is < $5)

---

## What You'll Carry Into Phase 1

After this phase, you own:
1. A **repeatable, destroyable foundation** — one command up, one command down
2. **IaC muscle memory** — you'll never click-to-create in production again
3. **The "why" behind remote state, drift detection, and Workload Identity**
4. **Your first ADR** — a habit that separates senior from junior
5. **Your first journal entry** — the start of your story library

## What's Coming in Phase 1

You'll deploy a real microservices app on GKE — **deliberately wrong**. No GitOps, no service mesh, no observability. Just raw `kubectl apply`. You'll feel the chaos. Then Phase 2 fixes it with ArgoCD.

---

## Common Mistakes in Phase 0 (Watch For These)

1. **Skipping billing alerts** — "I'll do it later." You won't. Do it first.
2. **Using `roles/owner` for the CI service account** — Overprivileged. Use `roles/editor` + specific roles.
3. **Storing SA keys in GitHub Secrets** — Use Workload Identity. Keys are a security anti-pattern.
4. **Not destroying after sessions** — VPC + NAT costs ~$1.50/day idle. That's $45/month for nothing.
5. **Gold-plating the Terraform modules** — You'll want to add variables for everything. Don't. YAGNI. Add complexity when pain demands it.
6. **Not writing the journal** — "I'll remember." You won't. Write it now.
