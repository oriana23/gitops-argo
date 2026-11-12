terraform {
  required_version = ">= 1.14"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
    argocd = {
      source  = "argoproj-labs/argocd"
      version = "~> 7.0"
    }
  }
}

# Proveedor de Kubernetes conectado a tu Minikube local
provider "kubernetes" {
  config_path = "~/.kube/config"
}

# Proveedor de Helm conectado a tu Minikube local
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

# 1. Crear el Namespace de Argo CD
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

# 2. Instalar Argo CD mediante Helm de forma automatizada
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.7.0"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
}

# Proveedor de ArgoCD para gestionar aplicaciones
# Lee la password desde el Secret de Kubernetes
provider "argocd" {
  server_addr = "argocd.local:443"
  username    = "admin"
  password    = kubernetes_secret.argocd_admin_password.data["password"]
  insecure    = true  # ignora verificación del certificado autofirmado
}
