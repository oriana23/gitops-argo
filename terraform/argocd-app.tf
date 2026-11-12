resource "argocd_application" "nginx" {
  metadata {
    name      = "nginx-app"
    namespace = "argocd"
  }
  spec {
    source {
      repo_url        = "https://github.com/oriana23/gitops-argo"
      path            = "apps/nginx-app"
      target_revision = "HEAD"

      helm {
        release_name = "nginx-app"
        values = <<-EOT
          replicaCount: 2
        EOT
        # podés sobreescribir valores del values.yaml desde acá
      }
    }
    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "nginx-app"
    }
    sync_policy {
      automated {
        prune       = true
        self_heal   = true
      }
      sync_options = ["CreateNamespace=true"]  # ArgoCD crea el namespace automáticamente
    }
  }
}
