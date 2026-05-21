output "namespaces" {
  description = "Created namespace names"
  value       = [for ns in kubernetes_namespace.namespaces : ns.metadata[0].name]
}

output "kubeconfig_path" {
  description = "Kubeconfig path used"
  value       = var.kubeconfig_path
}

output "service_account_name" {
  description = "ServiceAccount created for the app"
  value       = kubernetes_service_account.app.metadata[0].name
}
