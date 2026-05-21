terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }

  # Local backend — homelab has no remote state infra; fine for single-node k3s
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

resource "kubernetes_namespace" "namespaces" {
  for_each = toset(var.namespaces)

  metadata {
    name = each.value
    labels = {
      managed-by = "terraform"
    }
  }
}

resource "kubernetes_service_account" "app" {
  metadata {
    name      = var.app_name
    namespace = "apps"
    labels = {
      app        = var.app_name
      managed-by = "terraform"
    }
  }

  depends_on = [kubernetes_namespace.namespaces]
}

resource "kubernetes_cluster_role" "app" {
  metadata {
    name = "${var.app_name}-role"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "services", "endpoints"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "app" {
  metadata {
    name = "${var.app_name}-rolebinding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.app.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.app.metadata[0].name
    namespace = "apps"
  }
}
