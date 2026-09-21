"""
Generates 100% synthetic (fake) patient, encounter, and access-log data for the
dashboard demo. No real PHI is ever used — this is safe to commit, submit, and
show to your instructor.

Run:  python generate_synthetic_data.py
Output: patients.csv, encounters.csv, access_log.csv (in this folder)
"""
import csv
import random
from datetime import datetime, timedelta

random.seed(42)

FIRST_NAMES = ["Aarav", "Vihaan", "Ishaan", "Ananya", "Diya", "Priya", "Rohan",
               "Sara", "Kabir", "Meera", "Advait", "Naina", "Arjun", "Kavya"]
LAST_NAMES = ["Sharma", "Verma", "Patel", "Nair", "Reddy", "Gupta", "Iyer",
              "Das", "Khan", "Chowdhury", "Mehta", "Rao"]
DEPARTMENTS = ["Cardiology", "Orthopedics", "Pediatrics", "Oncology",
               "General Medicine", "Neurology", "Emergency"]
DIAGNOSES = ["Hypertension", "Type 2 Diabetes", "Fracture", "Asthma",
             "Migraine", "Influenza", "Routine Checkup", "Anemia", "COVID-19"]
USERS = ["dr_kapoor", "dr_singh", "nurse_iyer", "analyst_rao",
         "admin_devops", "dr_shah", "nurse_das"]
ACTIONS = ["VIEW_RECORD", "UPDATE_RECORD", "EXPORT_REPORT", "LOGIN",
           "FAILED_LOGIN", "DOWNLOAD_ANALYTICS", "DELETE_ATTEMPT_DENIED"]

N_PATIENTS = 300
N_ENCOUNTERS = 900
N_LOG_EVENTS = 1500

start_date = datetime(2026, 1, 1)


def rand_date(days_range=260):
    return start_date + timedelta(days=random.randint(0, days_range),
                                   hours=random.randint(0, 23),
                                   minutes=random.randint(0, 59))


# --- patients.csv (de-identified synthetic demographics) -------------------
with open("patients.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["patient_id", "age", "gender", "department", "region", "insurance_type"])
    for i in range(1, N_PATIENTS + 1):
        w.writerow([
            f"PT{i:05d}",
            random.randint(1, 90),
            random.choice(["M", "F", "Other"]),
            random.choice(DEPARTMENTS),
            random.choice(["East", "West", "North", "South", "Central"]),
            random.choice(["Government", "Private", "Self-pay"]),
        ])

# --- encounters.csv (visit-level synthetic records) -------------------------
with open("encounters.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["encounter_id", "patient_id", "visit_date", "department",
                "diagnosis", "length_of_stay_days", "cost_usd"])
    for i in range(1, N_ENCOUNTERS + 1):
        w.writerow([
            f"ENC{i:06d}",
            f"PT{random.randint(1, N_PATIENTS):05d}",
            rand_date().strftime("%Y-%m-%d"),
            random.choice(DEPARTMENTS),
            random.choice(DIAGNOSES),
            random.choice([0, 0, 0, 1, 2, 3, 5, 7]),
            round(random.uniform(50, 12000), 2),
        ])

# --- access_log.csv (simulates CloudTrail-style audit events) --------------
with open("access_log.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["timestamp", "user", "action", "resource", "source_ip", "result"])
    for i in range(N_LOG_EVENTS):
        action = random.choice(ACTIONS)
        result = "DENIED" if action in ("FAILED_LOGIN", "DELETE_ATTEMPT_DENIED") else "SUCCESS"
        w.writerow([
            rand_date().strftime("%Y-%m-%d %H:%M:%S"),
            random.choice(USERS),
            action,
            random.choice(["s3://healthcare-data/raw-phi/", "aurora://healthcaredb",
                            "s3://healthcare-data/analytics/"]),
            f"10.20.{random.randint(1,254)}.{random.randint(1,254)}",
            result,
        ])

print("Generated patients.csv, encounters.csv, access_log.csv")
