variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "namespaces" {
  description = "Namespaces to create"
  type        = list(string)
  default     = ["apps", "monitoring", "argocd", "sealed-secrets"]
}

variable "app_name" {
  description = "Application name"
  type        = string
  default     = "sample-app"
}
