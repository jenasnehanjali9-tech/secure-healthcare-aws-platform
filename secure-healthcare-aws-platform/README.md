# Secure Healthcare Data Management & Analytics Platform on AWS

A class-project-ready implementation integrating **Aurora, S3, KMS, IAM, AWS Config, and CloudTrail**,
plus a runnable analytics + security dashboard.

- `infrastructure/` — Terraform code that provisions everything on AWS
- `dashboard/` — Streamlit dashboard (runs standalone with demo data, or live against your AWS account)
- `data/` — synthetic (fake) healthcare data generator + pre-generated CSVs, used by the dashboard
- `scripts/` — one-command deploy / destroy / run scripts
- `docs/architecture.md` — architecture write-up + Mermaid diagram for your report/slides

---

## Fastest path: see the dashboard right now (no AWS account needed)

You don't need AWS credentials to demo the dashboard — it ships with synthetic data.

```bash
# 1. Unzip the project
unzip secure-healthcare-aws-platform.zip
cd secure-healthcare-aws-platform

# 2. Run the dashboard (creates a venv, installs deps, launches it)
chmod +x scripts/*.sh
./scripts/run_dashboard.sh
```

Then open **http://localhost:8501** in your browser. That's it.

If you're on Windows (no bash), run instead:
```powershell
cd dashboard
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
streamlit run app.py
```

---

## Full path: deploy the real AWS infrastructure

### Prerequisites

1. An AWS account (a free-tier/student account is fine — Aurora `db.t3.medium` is NOT free-tier, see "Cost" below).
2. [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) installed and configured:
   ```bash
   aws configure
   # Enter your AWS Access Key ID, Secret Access Key, region (e.g. us-east-1), output format (json)
   ```
3. [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5 installed.

### Step 1 — review and edit variables

Open `infrastructure/variables.tf` and, at minimum, change:
```hcl
variable "allowed_dashboard_cidr" {
  default = "0.0.0.0/0"   # CHANGE to "YOUR.IP.ADD.RESS/32" before applying
}
```
Find your IP with `curl ifconfig.me` and set the CIDR to `<that-ip>/32`.

### Step 2 — deploy

```bash
cd infrastructure
terraform init
terraform validate
terraform plan
terraform apply
```
Type `yes` when prompted. This takes ~15-20 minutes (Aurora cluster creation is the slow part).

Or just run the guided script from the project root:
```bash
./scripts/deploy.sh
```

### Step 3 — see what was created

```bash
terraform output
```
This prints the Aurora endpoint, S3 bucket names, KMS key ARNs, IAM role ARNs, and the Secrets Manager
ARN holding the generated database password (the password itself is never printed to your terminal —
retrieve it only when needed):
```bash
aws secretsmanager get-secret-value \
  --secret-id "$(terraform output -raw db_secret_arn)" \
  --query SecretString --output text
```

### Step 4 — run the dashboard against your real AWS account

```bash
cd ../
export AWS_REGION=us-east-1        # match the region you deployed to
./scripts/run_dashboard_live.sh
```
The dashboard will pull live AWS Config compliance results and live CloudTrail events. Patient/encounter
analytics stay on the synthetic CSVs (since a fresh Aurora cluster has no data yet — see below).

### Step 5 — (optional) load sample data into Aurora

```bash
# Get connection details
ENDPOINT=$(terraform -chdir=infrastructure output -raw aurora_cluster_endpoint)
SECRET_ARN=$(terraform -chdir=infrastructure output -raw db_secret_arn)
aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --query SecretString --output text > /tmp/dbcreds.json

# From a machine inside the VPC (e.g. an EC2 bastion in the public subnet, or AWS CloudShell
# with a VPC-connected environment), connect with psql:
psql "host=$ENDPOINT dbname=healthcaredb user=hc_admin sslmode=require"
```
Aurora is deployed in **private subnets only** by design (no public access), so you'll need a bastion
host or AWS Systems Manager Session Manager tunnel to reach it — this is intentional for a HIPAA-aligned
architecture. See "Extending this project" below if you want a bastion added.

### Step 6 — tear it down (avoid ongoing charges!)

```bash
./scripts/destroy.sh
```
or
```bash
cd infrastructure && terraform destroy
```

---

## Cost estimate (us-east-1, approximate)

| Resource | Approx. cost |
|---|---|
| Aurora `db.t3.medium` (1 instance) | ~$0.082/hr (~$60/mo if left running) |
| Aurora storage + I/O | usage-based, small for a demo |
| S3 storage | negligible for a class project |
| KMS CMKs | $1/month per key x 2 = $2/mo |
| AWS Config | ~$0.003 per configuration item recorded |
| CloudTrail | first trail is free for management events |
| **Total if you deploy and destroy within a day** | **usually a few dollars or less** |

**Run `terraform destroy` as soon as you're done recording your demo** to avoid Aurora's hourly charge accumulating.

---

## What each AWS service does in this project

- **Aurora (PostgreSQL-compatible)** — structured, transactional store for patient and encounter records. Encrypted at rest with a customer-managed KMS key, deployed only in private subnets, TLS-only connections enforced via parameter group.
- **S3** — data lake for raw PHI (locked-down `raw-phi/` prefix) and de-identified analytics extracts (`analytics/` prefix). Server-side encryption with KMS, versioning, public access fully blocked, bucket policy denies unencrypted or non-TLS uploads.
- **KMS** — two customer-managed keys (one for application data, one for CloudTrail logs) so a compromised data key can't be used to tamper with audit history. Automatic annual key rotation enabled.
- **IAM** — three least-privilege roles modeling real healthcare personas: `clinician` (Aurora read/write only), `analyst` (read-only on de-identified S3 data only), `admin` (infrastructure management, explicitly *denied* PHI read access — separation of duties). MFA required to assume any role; strict account-wide password policy.
- **AWS Config** — continuously records resource configuration and evaluates it against 9 managed rules: S3 encryption/public-access, RDS encryption/public-access, root MFA, IAM password policy, CloudTrail enabled, KMS key rotation.
- **CloudTrail** — multi-region trail with log file integrity validation, S3 data-event logging on the PHI bucket, CloudWatch Logs delivery, and a CloudWatch alarm + SNS topic that fires on any root-account usage.

## HIPAA Security Rule control mapping (for your report)

| Safeguard | Implementation | HIPAA reference |
|---|---|---|
| Encryption at rest | KMS CMKs on Aurora, S3, CloudTrail logs | §164.312(a)(2)(iv) |
| Encryption in transit | `rds.force_ssl=1`; S3 bucket policy denies non-TLS requests | §164.312(e)(1) |
| Access control / RBAC | IAM clinician/analyst/admin roles, least privilege, explicit denies | §164.312(a)(1) |
| Audit controls | CloudTrail multi-region trail + log file validation | §164.312(b) |
| Person/entity authentication, MFA | MFA required to assume any IAM role; strict password policy | §164.312(a)(2)(iii), (d) |
| Integrity controls | S3 object versioning; CloudTrail log file validation digests | §164.312(c)(1) |

---

## Project structure

```
secure-healthcare-aws-platform/
├── README.md                     <- you are here
├── infrastructure/                <- Terraform (Aurora, S3, KMS, IAM, Config, CloudTrail, VPC)
│   ├── versions.tf
│   ├── variables.tf
│   ├── vpc.tf
│   ├── kms.tf
│   ├── s3.tf
│   ├── aurora.tf
│   ├── iam.tf
│   ├── cloudtrail.tf
│   ├── config.tf
│   └── outputs.tf
├── dashboard/
│   ├── app.py                     <- Streamlit dashboard (demo + live AWS mode)
│   └── requirements.txt
├── data/
│   ├── generate_synthetic_data.py <- regenerate the fake data anytime
│   ├── patients.csv                (pre-generated, 300 synthetic patients)
│   ├── encounters.csv              (pre-generated, 900 synthetic encounters)
│   └── access_log.csv              (pre-generated, 1500 simulated audit events)
├── scripts/
│   ├── deploy.sh
│   ├── destroy.sh
│   ├── run_dashboard.sh           <- demo mode, no AWS needed
│   └── run_dashboard_live.sh      <- live mode, reads your real AWS account
└── docs/
    └── architecture.md            <- write-up + Mermaid diagram for your report/slides
```

## Using this for your class submission

1. **Report/paper**: use `docs/architecture.md` for the architecture section — it has a Mermaid diagram
   (renders directly on GitHub, or paste into https://mermaid.live to export a PNG) and the HIPAA control
   mapping table above.
2. **Live demo**: run `./scripts/run_dashboard.sh` right before your presentation — no AWS costs, no waiting for `terraform apply`.
3. **"We actually deployed it" proof**: if your instructor wants to see real AWS resources, run
   `terraform apply`, screenshot the AWS Console (RDS, S3, Config, CloudTrail) and `terraform output`,
   then `terraform destroy` afterward.
4. **Code walkthrough**: each `.tf` file is scoped to one AWS service so you can present them in order:
   VPC → KMS → S3 → Aurora → IAM → CloudTrail → Config.

## Extending this project (optional, for extra credit)

- Add a bastion host / AWS Systems Manager Session Manager to reach Aurora from your laptop.
- Add an ETL Lambda that de-identifies Aurora records and writes them to `s3://.../analytics/` on a schedule (EventBridge).
- Add AWS Config **conformance packs** (e.g. the AWS-provided HIPAA Security conformance pack) instead of individual rules for a more exhaustive control set.
- Add GuardDuty and Macie for threat detection and automated PII/PHI discovery in S3.
- Containerize the dashboard and deploy it on ECS Fargate behind an ALB with Cognito auth, instead of running it locally.

## Troubleshooting

- **`terraform apply` fails on IAM permissions** — your AWS user/role needs sufficiently broad permissions (IAM, RDS, S3, KMS, Config, CloudTrail, EC2/VPC). For a class account, `AdministratorAccess` is simplest.
- **Aurora takes a long time to appear** — this is normal; Aurora clusters typically take 10-15 minutes.
- **Dashboard shows "Could not reach AWS Config"** — confirm `aws sts get-caller-identity` works in the same shell you launched Streamlit from, and that `AWS_REGION` matches where you deployed.
- **Streamlit not found** — make sure you activated the virtual environment (`source dashboard/.venv/bin/activate`) or just re-run `./scripts/run_dashboard.sh`, which does this for you.
