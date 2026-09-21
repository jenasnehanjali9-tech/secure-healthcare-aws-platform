"""
Secure Healthcare Data Management & Analytics Platform — Dashboard
--------------------------------------------------------------------
Run locally with demo data (no AWS needed):
    streamlit run app.py

Run against a real deployed AWS account (after terraform apply):
    export USE_LIVE_AWS=true
    export AWS_REGION=us-east-1
    streamlit run app.py

When USE_LIVE_AWS is not set, the dashboard reads the bundled synthetic
CSVs in ../data/ and simulated compliance/audit data, so it always runs
out of the box for a class demo.
"""
import os
import json
from datetime import datetime

import pandas as pd
import streamlit as st
import plotly.express as px

USE_LIVE_AWS = os.environ.get("USE_LIVE_AWS", "false").lower() == "true"
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")

st.set_page_config(
    page_title="Secure Healthcare Data Platform",
    page_icon="🏥",
    layout="wide",
)

# ----------------------------------------------------------------------------
# Data loading
# ----------------------------------------------------------------------------

@st.cache_data
def load_demo_data():
    patients = pd.read_csv(os.path.join(DATA_DIR, "patients.csv"))
    encounters = pd.read_csv(os.path.join(DATA_DIR, "encounters.csv"), parse_dates=["visit_date"])
    access_log = pd.read_csv(os.path.join(DATA_DIR, "access_log.csv"), parse_dates=["timestamp"])
    return patients, encounters, access_log


@st.cache_data(ttl=300)
def load_live_config_compliance():
    """Pull real AWS Config rule compliance if boto3 + credentials are available."""
    import boto3
    client = boto3.client("config", region_name=AWS_REGION)
    rules = client.describe_config_rules()["ConfigRules"]
    rows = []
    for r in rules:
        name = r["ConfigRuleName"]
        try:
            summary = client.get_compliance_details_by_config_rule(ConfigRuleName=name)
            results = summary.get("EvaluationResults", [])
            compliant = sum(1 for e in results if e["ComplianceType"] == "COMPLIANT")
            noncompliant = sum(1 for e in results if e["ComplianceType"] == "NON_COMPLIANT")
        except Exception:
            compliant, noncompliant = 0, 0
        rows.append({"rule": name, "compliant": compliant, "non_compliant": noncompliant})
    return pd.DataFrame(rows)


@st.cache_data(ttl=300)
def load_live_cloudtrail_events(max_results=50):
    import boto3
    client = boto3.client("cloudtrail", region_name=AWS_REGION)
    resp = client.lookup_events(MaxResults=max_results)
    events = []
    for e in resp.get("Events", []):
        events.append({
            "timestamp": e.get("EventTime"),
            "user": e.get("Username", "unknown"),
            "action": e.get("EventName"),
            "resource": ", ".join([r.get("ResourceName", "") for r in e.get("Resources", [])]),
        })
    return pd.DataFrame(events)


def simulated_compliance_summary():
    """Simulated AWS Config rule state for demo mode — mirrors the rules defined in
    infrastructure/config.tf so the dashboard tells the same compliance story a real
    deployment would."""
    rules = [
        ("s3-bucket-sse-enabled", 3, 0),
        ("s3-public-read-prohibited", 3, 0),
        ("s3-public-write-prohibited", 3, 0),
        ("rds-storage-encrypted", 1, 0),
        ("rds-instance-public-access-check", 1, 0),
        ("root-account-mfa-enabled", 1, 0),
        ("iam-password-policy", 1, 0),
        ("cloudtrail-enabled", 1, 0),
        ("cmk-backing-key-rotation-enabled", 2, 0),
    ]
    return pd.DataFrame(rules, columns=["rule", "compliant", "non_compliant"])


# ----------------------------------------------------------------------------
# Sidebar
# ----------------------------------------------------------------------------

st.sidebar.title("🏥 Platform Console")
st.sidebar.markdown(f"**Region:** {AWS_REGION}")
st.sidebar.markdown("---")
page = st.sidebar.radio(
    "Navigate",
    ["Overview", "Patient & Encounter Analytics", "Security & Compliance", "Audit Log (CloudTrail)", "Architecture"],
)
st.sidebar.markdown("---")
st.sidebar.caption(
    "All patient data shown here is synthetically generated for demonstration. "
    "No real PHI is stored or displayed."
)

patients, encounters, access_log = load_demo_data()

# ----------------------------------------------------------------------------
# Overview
# ----------------------------------------------------------------------------

if page == "Overview":
    st.title("Secure Healthcare Data Management & Analytics Platform")
    st.caption("AWS Aurora · S3 · KMS · IAM · AWS Config · CloudTrail")

    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Total Patients", f"{len(patients):,}")
    c2.metric("Total Encounters", f"{len(encounters):,}")
    c3.metric("Total Care Cost (synthetic)", f"${encounters['cost_usd'].sum():,.0f}")
    denied = (access_log["result"] == "DENIED").sum()
    c4.metric("Denied/Failed Access Attempts", f"{denied}", delta=None)

    st.markdown("### What this platform does")
    st.markdown(
        """
- **Aurora (PostgreSQL, encrypted)** — stores structured patient & encounter records, private subnet only, TLS enforced.
- **S3 (KMS-encrypted data lake)** — raw PHI in a locked-down `raw-phi/` prefix and de-identified `analytics/` prefix for BI use.
- **KMS** — customer-managed keys with automatic annual rotation encrypt Aurora storage, S3 objects, and CloudTrail logs.
- **IAM** — three least-privilege roles (clinician, analyst, admin) with explicit `Deny` statements enforcing separation of duties.
- **AWS Config** — continuously evaluates 9 managed rules (encryption, public access, MFA, password policy, log validation) against HIPAA-aligned controls.
- **CloudTrail** — multi-region trail with log file validation, S3 data events, and a CloudWatch alarm on root-account usage.
        """
    )

    st.markdown("### Encounters over time")
    ts = encounters.groupby(encounters["visit_date"].dt.to_period("W")).size()
    ts.index = ts.index.astype(str)
    fig = px.line(x=ts.index, y=ts.values, labels={"x": "Week", "y": "Encounters"})
    st.plotly_chart(fig, use_container_width=True)

# ----------------------------------------------------------------------------
# Patient & Encounter Analytics
# ----------------------------------------------------------------------------

elif page == "Patient & Encounter Analytics":
    st.title("Patient & Encounter Analytics")
    st.caption("Aggregated from the de-identified `analytics/` prefix — no direct-identifiers are ever exposed here.")

    col1, col2 = st.columns(2)
    with col1:
        dept_counts = encounters["department"].value_counts().reset_index()
        dept_counts.columns = ["department", "encounters"]
        fig = px.bar(dept_counts, x="department", y="encounters", title="Encounters by Department")
        st.plotly_chart(fig, use_container_width=True)

    with col2:
        diag_counts = encounters["diagnosis"].value_counts().reset_index()
        diag_counts.columns = ["diagnosis", "count"]
        fig = px.pie(diag_counts, names="diagnosis", values="count", title="Diagnosis Mix")
        st.plotly_chart(fig, use_container_width=True)

    col3, col4 = st.columns(2)
    with col3:
        fig = px.histogram(patients, x="age", nbins=20, title="Patient Age Distribution")
        st.plotly_chart(fig, use_container_width=True)
    with col4:
        cost_by_dept = encounters.groupby("department")["cost_usd"].mean().reset_index()
        fig = px.bar(cost_by_dept, x="department", y="cost_usd", title="Average Cost per Encounter by Department")
        st.plotly_chart(fig, use_container_width=True)

    st.markdown("### Regional insurance mix")
    region_ins = pd.crosstab(patients["region"], patients["insurance_type"])
    st.dataframe(region_ins, use_container_width=True)

# ----------------------------------------------------------------------------
# Security & Compliance
# ----------------------------------------------------------------------------

elif page == "Security & Compliance":
    st.title("Security & Compliance — AWS Config")

    if USE_LIVE_AWS:
        try:
            compliance_df = load_live_config_compliance()
            st.success("Showing live AWS Config rule evaluations from your account.")
        except Exception as e:
            st.warning(f"Could not reach AWS Config ({e}). Showing simulated data instead.")
            compliance_df = simulated_compliance_summary()
    else:
       
        compliance_df = simulated_compliance_summary()

    compliance_df["status"] = compliance_df.apply(
        lambda r: "✅ COMPLIANT" if r["non_compliant"] == 0 else "❌ NON-COMPLIANT", axis=1
    )
    st.dataframe(compliance_df, use_container_width=True)

    fig = px.bar(
        compliance_df, x="rule", y=["compliant", "non_compliant"],
        title="Config Rule Compliance (resources evaluated)", barmode="stack"
    )
    fig.update_layout(xaxis_tickangle=-30)
    st.plotly_chart(fig, use_container_width=True)

    st.markdown("### HIPAA-aligned control mapping")
    st.table(pd.DataFrame([
        ("Encryption at rest", "KMS CMKs on Aurora, S3, CloudTrail logs", "§164.312(a)(2)(iv)"),
        ("Encryption in transit", "rds.force_ssl=1, S3 bucket policy denies non-TLS", "§164.312(e)(1)"),
        ("Access control / RBAC", "IAM clinician/analyst/admin roles, least privilege", "§164.312(a)(1)"),
        ("Audit controls", "CloudTrail multi-region + log file validation", "§164.312(b)"),
        ("Automatic logoff / MFA", "IAM password policy + MFA-required assume-role", "§164.312(a)(2)(iii)"),
        ("Integrity controls", "S3 versioning + CloudTrail log validation digest", "§164.312(c)(1)"),
    ], columns=["Safeguard", "Implementation", "HIPAA Reference"]))

# ----------------------------------------------------------------------------
# Audit log
# ----------------------------------------------------------------------------

elif page == "Audit Log (CloudTrail)":
    st.title("Audit Log")

    if USE_LIVE_AWS:
        try:
            log_df = load_live_cloudtrail_events()
            st.success("Showing the most recent live CloudTrail events.")
        except Exception as e:
            st.warning(f"Could not reach CloudTrail ({e}). Showing simulated audit log instead.")
            log_df = access_log.sort_values("timestamp", ascending=False).head(200)
    else:
                log_df = access_log.sort_values("timestamp", ascending=False).head(200)

    col1, col2 = st.columns(2)
    with col1:
        user_filter = st.multiselect("Filter by user", sorted(access_log["user"].unique()))
    with col2:
        action_filter = st.multiselect("Filter by action", sorted(access_log["action"].unique()))

    filtered = log_df.copy()
    if user_filter:
        filtered = filtered[filtered["user"].isin(user_filter)]
    if action_filter:
        filtered = filtered[filtered["action"].isin(action_filter)]

    st.dataframe(filtered, use_container_width=True, height=420)

    denied = access_log[access_log["result"] == "DENIED"]
    if len(denied):
        st.warning(f"{len(denied)} denied/failed events in the full log — review for possible brute-force or unauthorized access attempts.")
        by_user = denied["user"].value_counts().reset_index()
        by_user.columns = ["user", "denied_events"]
        fig = px.bar(by_user, x="user", y="denied_events", title="Denied Events by User")
        st.plotly_chart(fig, use_container_width=True)

# ----------------------------------------------------------------------------
# Architecture
# ----------------------------------------------------------------------------

elif page == "Architecture":
    st.title("Architecture")
    st.markdown("""
```
                    ┌───────────────────────────────────────────────────────┐
                    │                      AWS Account                       │
                    │                                                        │
   Clinician ───────┼──▶ IAM Role (clinician) ──▶ Aurora PostgreSQL (private │
   (MFA required)   │                              subnet, KMS-encrypted,    │
                    │                              TLS enforced)             │
                    │                                    │                   │
   Analyst ─────────┼──▶ IAM Role (analyst)  ──▶ S3 analytics/ prefix        │
   (MFA required)   │                              (KMS-encrypted)           │
                    │                                    │                   │
   Admin ───────────┼──▶ IAM Role (admin, no PHI read) ──▶ Infra mgmt        │
                    │                                                        │
                    │   ┌─────────────┐   ┌──────────────┐  ┌─────────────┐  │
                    │   │  AWS Config │   │  CloudTrail  │  │  KMS CMKs   │  │
                    │   │  9 rules    │   │  multi-region│  │  data + log │  │
                    │   │  HIPAA-     │   │  log validate│  │  key, auto  │  │
                    │   │  aligned    │   │  + CW alarm  │  │  rotation   │  │
                    │   └──────┬──────┘   └───────┬──────┘  └─────────────┘  │
                    │          │                  │                          │
                    │          ▼                  ▼                          │
                    │   S3 config-bucket   S3 access-logs-bucket             │
                    │   (private, SSE)     (private, SSE, CloudTrail dest)   │
                    │                                                        │
                    │   Streamlit Dashboard (this app) ──▶ reads Config,     │
                    │   EC2 w/ instance role, no infra    CloudTrail, S3     │
                    │   or PHI write access               analytics data    │
                    └───────────────────────────────────────────────────────┘
```
    """)
    st.markdown("See `docs/architecture.md` for the full write-up and a Mermaid diagram you can paste into draw.io, Lucidchart, or your report.")
