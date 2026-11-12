# GitOps Lab — ArgoCD + Terraform + Kubernetes

## Descripción

Este repositorio centraliza toda la infraestructura y los manifiestos de aplicaciones de un stack GitOps completo en Kubernetes (Minikube local) usando Terraform. Incluye la instalación de ArgoCD, configuración de Ingress NGINX, despliegue automatizado de una aplicación nginx mediante un Helm chart propio, y un stack de observabilidad con Prometheus y Grafana gestionado como app-of-apps.

---

## Arquitectura

```
GitHub Repo (oriana23/gitops-argo)
        │
        │  ArgoCD monitorea y sincroniza
        ▼
   Kubernetes (Minikube)
        │
        ├── Namespace: argocd
        │     ├── ArgoCD (instalado via Helm)
        │     └── Ingress → argocd.local
        │
        ├── Namespace: nginx-app
        │     ├── Deployment (2 réplicas nginx)
        │     ├── Service (ClusterIP)
        │     ├── Ingress → nginx.local
        │     └── PodDisruptionBudget (minAvailable: 1)
        │
        └── Namespace: monitoring
              ├── Prometheus Operator
              ├── Prometheus
              └── Grafana
```

---

## Requisitos previos

- Minikube instalado y corriendo
- Terraform >= 1.14
- kubectl configurado con `~/.kube/config`
- Ingress NGINX habilitado en Minikube:
  ```bash
  minikube addons enable ingress
  ```

---

## Estructura del repositorio

```
gitops-argo/
├── terraform/                    # Infraestructura como código
│   ├── provider.tf               # Providers + instalación de ArgoCD
│   ├── ingress.tf                # Ingress para argocd.local
│   ├── argocd-app.tf             # Application nginx gestionada por ArgoCD
│   ├── operators.tf              # ArgoCD Project + app-of-apps para operadores
│   ├── secrets.tf                # Secret con la password de ArgoCD
│   ├── variables.tf              # Variable argocd_password
│   └── outputs.tf                # (reservado para outputs futuros)
│
├── apps/                         # Helm charts de las aplicaciones
│   ├── nginx-app/                # Chart de la app nginx
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       ├── ingress.yaml
│   │       ├── pdb.yaml
│   │       └── configmap.yaml
│   │
│   └── operators/                # App-of-apps para operadores
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── minikube-values.yaml
│       └── templates/
│           ├── prometheus-stack.yaml
│           └── ...
│
└── README.md
```

---

## Archivos Terraform

### `provider.tf`
Configura los providers de **Kubernetes**, **Helm** y **ArgoCD**, todos conectados al cluster local via `~/.kube/config`. Crea el namespace `argocd` e instala ArgoCD via Helm chart versión `7.7.0` desde el repo oficial. El provider ArgoCD lee la password desde el Secret de Kubernetes, nunca desde texto plano.

### `ingress.tf`
Crea el Ingress que expone ArgoCD en `argocd.local`. Configurado con SSL passthrough y backend HTTPS hacia `argocd-server:443`.

### `argocd-app.tf`
Define la Application de ArgoCD que apunta al repo `https://github.com/oriana23/gitops-argo`, path `apps/nginx-app/`. Namespace destino `nginx-app` creado automáticamente. Sync automático con `prune` y `selfHeal`. Sobreescribe `replicaCount: 2`.

### `secrets.tf`
Crea el Secret `argocd-admin-credentials` en el namespace `argocd`. La password se guarda de forma segura en Kubernetes y nunca queda en el código fuente.

### `operators.tf`
Crea el ArgoCD Project `local-operators` que define qué repos y namespaces puede usar. Crea la Application raíz `operators` (patrón app-of-apps) apuntando a `apps/operators/`. ArgoCD renderiza el chart y genera automáticamente la Application `prometheus-stack`.

---

## Archivos del chart `apps/nginx-app`

### `Chart.yaml`
Identifica la carpeta como un chart Helm válido. Define el nombre `nginx-app`, versión del chart `0.1.0` y versión de la app `1.27`.

### `values.yaml`
Centraliza toda la configuración configurable: imagen Docker, réplicas, tipo de servicio, puerto, hostname del Ingress y límites de recursos. Es el único archivo que hay que editar para cambiar el comportamiento de la app.

### `templates/deployment.yaml`
Define el Deployment de nginx. Usa `{{ .Values.* }}` para los valores configurables y `{{ .Release.Name }}` como identificador de recursos. Incluye `livenessProbe`, `readinessProbe` y un `volumeMount` que monta el ConfigMap con la página HTML custom en `/usr/share/nginx/html`.

### `templates/service.yaml`
Service ClusterIP que expone los pods en el puerto 80. Es el backend que usa el Ingress para enrutar el tráfico.

### `templates/ingress.yaml`
Ingress que enruta el tráfico de `nginx.local/` al Service de nginx. Hace accesible la app desde `http://nginx.local`.

### `templates/pdb.yaml`
PodDisruptionBudget con `minAvailable: 1`. Garantiza que durante updates o mantenimiento del nodo siempre quede al menos un pod disponible.

### `templates/configmap.yaml`
Almacena una página HTML custom que nginx sirve como página de inicio, montada como volumen en el Deployment. Al ser un ConfigMap, el HTML se puede modificar con un commit sin reconstruir la imagen Docker.

---

## Archivos del chart `apps/operators`

### `Chart.yaml`
Identifica la carpeta como chart Helm de tipo `application`. Es el chart raíz del patrón app-of-apps.

### `values.yaml`
Esquema base con todos los operadores en `enabled: false`. Define la estructura configurable del chart.

### `minikube-values.yaml`
Valores reales para el entorno local. Habilita solo `prometheusStack: true` con versión `93.2.0`. ArgoCD lo usa al renderizar el chart.

### `templates/prometheus-stack.yaml`
Genera la Application de ArgoCD `prometheus-stack` que instala `kube-prometheus-stack` desde el repo oficial de Prometheus Community. Despliega Prometheus, el Prometheus Operator y Grafana en el namespace `monitoring`.

---

## Mejoras de buenas prácticas aplicadas

### Seguridad
- Password de ArgoCD en un **Secret de Kubernetes** (`argocd-admin-credentials`), nunca en el código

### Resiliencia
- **PodDisruptionBudget**: mínimo 1 pod disponible durante updates o mantenimiento
- **livenessProbe**: reinicia el pod si no responde en `http://:80/`
- **readinessProbe**: no envía tráfico hasta que el pod esté listo

---

## Despliegue

### 1. Obtener la password inicial de ArgoCD
```bash
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 -d
```

### 2. Inicializar Terraform
```bash
cd terraform
terraform init
```

### 3. Aplicar
```bash
terraform apply -var="argocd_password=TU_PASSWORD"
```

### 4. Agregar entradas en `/etc/hosts`
```bash
echo "$(minikube ip)  argocd.local" | sudo tee -a /etc/hosts
echo "$(minikube ip)  nginx.local"  | sudo tee -a /etc/hosts
```

---

## Acceso

| Servicio | URL | Credenciales |
|---|---|---|
| ArgoCD UI | https://argocd.local | admin / password del paso 1 |
| nginx app | http://nginx.local | — |
| Grafana | http://localhost:3000 | admin / ver abajo |

### Acceder a Grafana
```bash
kubectl -n monitoring port-forward service/prometheus-stack-grafana 3000:80
```

Obtener password de Grafana:
```bash
kubectl -n monitoring get secret prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 --decode && echo
```

---

## Verificación

```bash
# Estado de todas las Applications en ArgoCD
kubectl get application -n argocd

# Pods de nginx
kubectl get pods -n nginx-app

# PodDisruptionBudget
kubectl get pdb -n nginx-app

# Probes del deployment
kubectl describe deployment nginx-app -n nginx-app | grep -A 5 "Liveness\|Readiness"

# Secret de ArgoCD
kubectl get secret argocd-admin-credentials -n argocd

# Pods de Prometheus y Grafana
kubectl get pods -n monitoring
```

---

## Progreso

| Día | Avance |
|---|---|
| Día 1 | Instalación de ArgoCD con Helm + Ingress configurado. Acceso a UI en argocd.local |
| Día 2 | Helm chart propio en GitHub. Application nginx con namespace dedicado e Ingress. Buenas prácticas: Secret para password, PodDisruptionBudget, livenessProbe, readinessProbe, ConfigMap con HTML custom. Stack de observabilidad con Prometheus + Grafana via app-of-apps. Migración a repo único `gitops-argo` |
