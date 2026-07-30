# EZIN Infrastructure

This directory contains the deployment boundary for production infrastructure. Firebase configuration is defined at the repository root, while Terraform modules under `infrastructure/terraform` describe Google Cloud resources that are not created directly by Firebase CLI.

## Environments

- `staging`: pre-production validation with Firebase emulators and isolated Google Cloud resources.
- `production`: release environment with restricted service accounts, Secret Manager access, monitoring, and audit retention.

## Secrets

Store provider credentials in Google Secret Manager. Do not commit secrets, local `.env` files, service account JSON, signing certificates, provisioning profiles, or broker credentials.

## Deployment order

1. Apply Terraform for project APIs, service accounts, Secret Manager entries, and monitoring alerts.
2. Deploy Firestore rules and indexes with Firebase CLI.
3. Deploy Cloud Functions after CI passes lint, tests, and TypeScript compilation.
4. Validate Cloud Monitoring dashboards and alert notification channels.
