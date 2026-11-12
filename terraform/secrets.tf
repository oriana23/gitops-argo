# Secret de Kubernetes para la password de ArgoCD
# Se crea antes que el provider argocd lo consuma
resource "kubernetes_secret" "argocd_admin_password" {
  metadata {
    name      = "argocd-admin-credentials"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }

  data = {
    password = var.argocd_password
  }

  type = "Opaque"

  depends_on = [kubernetes_namespace.argocd]
}
