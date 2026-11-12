# ArgoCD Project para los operadores
resource "argocd_project" "local_operators" {
  metadata {
    name      = "local-operators"
    namespace = "argocd"
  }

  spec {
    description = "Operadores portables para el laboratorio Kubernetes local"

    # Repos que puede usar este project
    source_repos = [
      "https://github.com/oriana23/gitops-argo",
      "git@github.com:teracloud-io/operators-kubernetes-ori.git",
      "https://prometheus-community.github.io/helm-charts",
      "https://charts.jetstack.io",
      "https://charts.external-secrets.io",
      "https://kedacore.github.io/charts",
      "https://cloudnative-pg.github.io/charts",
      "https://kubernetes.github.io/ingress-nginx",
      "https://argoproj.github.io/argo-helm",
    ]

    # Namespaces donde puede desplegar
    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "argocd"
    }
    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "monitoring"
    }
    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "kube-system"
    }

    # Permite crear recursos a nivel de cluster (CRDs, ClusterRoles, etc.)
    cluster_resource_whitelist {
      group = "*"
      kind  = "*"
    }

    namespace_resource_whitelist {
      group = "*"
      kind  = "*"
    }
  }
}

# Application raíz (app-of-apps) que genera la Application de Prometheus
resource "argocd_application" "operators" {
  metadata {
    name      = "operators"
    namespace = "argocd"
  }

  spec {
    project = argocd_project.local_operators.metadata[0].name

    source {
      repo_url        = "git@github.com:teracloud-io/operators-kubernetes-ori.git"
      path            = "operators"
      target_revision = "HEAD"

      helm {
        release_name = "operators"
        value_files  = ["minikube-values.yaml"]
      }
    }

    destination {
      server    = "https://kubernetes.default.svc"
      namespace = "argocd"
    }

    sync_policy {
      automated {
        prune     = true
        self_heal = true
      }
      sync_options = ["CreateNamespace=true", "ServerSideApply=true"]
    }
  }

  depends_on = [argocd_project.local_operators, argocd_repository.operators]
}
