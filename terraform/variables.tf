variable "argocd_password" {
  description = "Password del usuario admin de ArgoCD"
  type        = string
  sensitive   = true
}

variable "operators_ssh_key" {
  description = "Clave SSH privada para acceder al repo privado de operadores"
  type        = string
  sensitive   = true
}
