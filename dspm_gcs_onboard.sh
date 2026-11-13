#!/usr/bin/env bash
# DSPM GCS Connect - customer setup. Run in the customer's own project (Cloud Shell) as a project
# Owner. The command is shown in FirewallX with both values filled in:
#   curl -sf <SCRIPT_URL> | bash -s -- <YOUR_PROJECT_ID> <FIREWALLX_SERVICE_ACCOUNT>
#
# Two Google accounts are involved:
#   - FirewallX's own service account (the second argument), which belongs to FirewallX
#   - a read-only service account (dspm-gcs-readonly) this script creates in YOUR project
# The script lets FirewallX's account request short-lived tokens for yours, and nothing else. No
# key or secret is created, downloaded or sent. Revoke at any time by deleting the service account
# or removing the Token Creator grant.
#
# Safe to re-run: every step creates or updates.
set -euo pipefail

echo "=========================================================="
echo "DSPM GCS Connect - Setup"
echo "=========================================================="

if [ $# -lt 2 ]; then
  echo "Usage: curl -sf <SCRIPT_URL> | bash -s -- <YOUR_PROJECT_ID> <FIREWALLX_SERVICE_ACCOUNT>"
  echo "Copy the full command from FirewallX; it includes both values."
  exit 1
fi

CUSTOMER_PROJECT_ID="$1"
PLATFORM_SERVICE_ACCOUNT="$2"

case "${PLATFORM_SERVICE_ACCOUNT}" in
  *@*.iam.gserviceaccount.com) ;;
  *)
    echo "The second value must be FirewallX's service account email (ends with .iam.gserviceaccount.com)."
    exit 1
    ;;
esac

echo "Connecting project: ${CUSTOMER_PROJECT_ID}"
echo "FirewallX service account: ${PLATFORM_SERVICE_ACCOUNT}"
gcloud config set project "${CUSTOMER_PROJECT_ID}"

SERVICE_ACCOUNT_NAME="dspm-gcs-readonly"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${CUSTOMER_PROJECT_ID}.iam.gserviceaccount.com"
CUSTOM_ROLE_ID="dspmGcsReadOnly"

# What a scan reads: list buckets, read each bucket's settings and IAM policy, list its objects.
# None of these can read object contents or change anything.
ROLE_PERMISSIONS="storage.buckets.list,storage.buckets.get,storage.buckets.getIamPolicy,storage.objects.list"

echo ""
echo "[1/5] Enabling required APIs..."
# cloudresourcemanager is what "gcloud projects add-iam-policy-binding" calls; in a new project it
# is off, and gcloud cannot ask to enable it when this script is piped into bash.
gcloud services enable iam.googleapis.com cloudresourcemanager.googleapis.com storage.googleapis.com \
  --project="${CUSTOMER_PROJECT_ID}"

echo "[2/5] Creating the read-only service account..."
if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_EMAIL}" --project="${CUSTOMER_PROJECT_ID}" >/dev/null 2>&1; then
  echo "    (service account already exists, continuing)"
else
  gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
    --project="${CUSTOMER_PROJECT_ID}" \
    --display-name="DSPM Read-Only GCS Discovery"
  # a new service account takes a few seconds to be visible to IAM; granting on it sooner can fail
  sleep 10
fi

echo "[3/5] Creating or updating the read-only custom role..."
if gcloud iam roles describe "${CUSTOM_ROLE_ID}" --project="${CUSTOMER_PROJECT_ID}" >/dev/null 2>&1; then
  gcloud iam roles update "${CUSTOM_ROLE_ID}" \
    --project="${CUSTOMER_PROJECT_ID}" \
    --permissions="${ROLE_PERMISSIONS}"
else
  gcloud iam roles create "${CUSTOM_ROLE_ID}" \
    --project="${CUSTOMER_PROJECT_ID}" \
    --title="DSPM GCS Read-Only" \
    --description="List buckets, read bucket settings and IAM policy, list objects. No content access, no writes." \
    --permissions="${ROLE_PERMISSIONS}" \
    --stage="GA"
fi

echo "[4/5] Granting that role to the read-only service account..."
gcloud projects add-iam-policy-binding "${CUSTOMER_PROJECT_ID}" \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="projects/${CUSTOMER_PROJECT_ID}/roles/${CUSTOM_ROLE_ID}" \
  --condition=None

echo "[5/5] Letting FirewallX's service account (and only it) impersonate the read-only one..."
gcloud iam service-accounts add-iam-policy-binding "${SERVICE_ACCOUNT_EMAIL}" \
  --project="${CUSTOMER_PROJECT_ID}" \
  --member="serviceAccount:${PLATFORM_SERVICE_ACCOUNT}" \
  --role="roles/iam.serviceAccountTokenCreator" \
  --condition=None

echo ""
echo "=========================================================="
echo "SETUP COMPLETE - no keys, no secrets created."
echo ""
echo "Enter these two values in FirewallX:"
echo "  Project ID:      ${CUSTOMER_PROJECT_ID}"
echo "  Service Account: ${SERVICE_ACCOUNT_EMAIL}"
echo "=========================================================="
