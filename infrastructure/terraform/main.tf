terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

variable "project_id" {
  type        = string
  description = "Google Cloud project ID for the EZIN environment."
}

variable "region" {
  type        = string
  description = "Primary region for Cloud Run and regional services."
  default     = "us-central1"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  required_services = toset([
    "cloudfunctions.googleapis.com",
    "run.googleapis.com",
    "cloudscheduler.googleapis.com",
    "firestore.googleapis.com",
    "firebase.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudbuild.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com"
  ])
}

resource "google_project_service" "required" {
  for_each           = local.required_services
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_service_account" "worker" {
  account_id   = "ezin-worker"
  display_name = "EZIN backend worker service account"
}

resource "google_secret_manager_secret" "llm_provider_keys" {
  secret_id = "ezin-llm-provider-keys"
  replication {
    auto {}
  }
  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_iam_member" "worker_secret_reader" {
  secret_id = google_secret_manager_secret.llm_provider_keys.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.worker.email}"
}
