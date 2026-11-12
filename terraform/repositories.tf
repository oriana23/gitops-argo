# Registro del repo público gitops-argo en ArgoCD
resource "argocd_repository" "gitops_argo" {
  repo = "https://github.com/oriana23/gitops-argo"
  type = "git"
}

# Registro del repo privado de operadores con credenciales SSH
resource "argocd_repository" "operators" {
  repo            = "git@github.com:teracloud-io/operators-kubernetes-ori.git"
  type            = "git"
  ssh_private_key = var.operators_ssh_key
}
