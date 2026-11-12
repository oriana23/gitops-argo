# ArgoCD + Ingress NGINX — Proyecto GitOps con Terraform

## Descripción

Este proyecto implementa un stack GitOps completo en Kubernetes (Minikube local) usando Terraform. Incluye la instalación de ArgoCD, configuración de Ingress NGINX, despliegue automatizado de una aplicación nginx mediante un Helm chart propio, y un stack de observabilidad con Prometheus y Grafana gestionado como app-of-apps.

---

## Arquitectura

```
GitHub Repo (oriana23/argocd)
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

## Estructura del proyecto Terraform

```
argocd-ingress-proyecto/
├── provider.tf       # Providers (Kubernetes, Helm, ArgoCD) + instalación de ArgoCD
├── ingress.tf        # Ingress para acceder a ArgoCD en argocd.local
├── argocd-app.tf     # Application de ArgoCD que despliega nginx desde GitHub
├── operators.tf      # ArgoCD Project + Application app-of-apps para operadores
├── secrets.tf        # Secret de Kubernetes con la password de ArgoCD
├── variables.tf      # Variable argocd_password
├── outputs.tf        # (reservado para outputs futuros)
└── README.md
```

---

## Archivos Terraform

### `provider.tf`
- Configura los providers de **Kubernetes**, **Helm** y **ArgoCD**
- Crea el namespace `argocd`
- Instala ArgoCD via Helm chart versión `7.7.0` desde el repo oficial
- El provider ArgoCD lee la password desde el Secret de Kubernetes (no desde texto plano)

### `ingress.tf`
- Crea un Ingress con NGINX para exponer ArgoCD en `argocd.local`
- Configurado con SSL passthrough y backend HTTPS hacia `argocd-server:443`

### `argocd-app.tf`
- Define la Application de ArgoCD que apunta al repo `https://github.com/oriana23/argocd`
- Path del chart: `nginx-app/`
- Namespace destino: `nginx-app` (creado automáticamente con `CreateNamespace=true`)
- Sync automático con `prune` y `selfHeal` habilitados
- Sobreescribe `replicaCount: 2` desde Terraform

### `secrets.tf`
- Crea el Secret `argocd-admin-credentials` en el namespace `argocd`
- Almacena la password de forma segura en Kubernetes en lugar de texto plano en el código

### `operators.tf`
- Crea el ArgoCD Project `local-operators` con los repos y namespaces permitidos
- Crea la Application raíz `operators` (patrón app-of-apps) que apunta a `operators/` en el repo
- ArgoCD renderiza el chart y genera automáticamente la Application `prometheus-stack`

---

## Repo de manifiestos

**`https://github.com/oriana23/argocd`**

```
argocd/
├── nginx-app/                    # Helm chart de la app nginx
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml       # Con livenessProbe y readinessProbe + volumeMount
│       ├── service.yaml
│       ├── ingress.yaml
│       ├── pdb.yaml              # PodDisruptionBudget
│       └── configmap.yaml        # Página HTML custom servida por nginx
│
└── operators/                    # App-of-apps para operadores (basado en teracloud-io)
    ├── Chart.yaml
    ├── values.yaml
    ├── minikube-values.yaml      # Valores específicos para Minikube (solo Prometheus)
    └── templates/
        ├── prometheus-stack.yaml
        ├── cert-manager.yaml
        ├── keda.yaml
        └── ...
```

### Descripción de cada archivo del chart `nginx-app`

#### `Chart.yaml`
Identifica la carpeta como un chart Helm válido. Define el nombre `nginx-app`, la versión del chart `0.1.0` y la versión de la aplicación `1.27` (imagen de nginx). Sin este archivo Helm no reconoce el directorio como chart.

#### `values.yaml`
Centraliza toda la configuración configurable del chart. Define la imagen Docker, cantidad de réplicas, tipo de servicio, puerto, hostname del Ingress y límites de recursos CPU/memoria. Es el único archivo que hay que editar para cambiar el comportamiento de la app sin tocar los templates.

#### `templates/deployment.yaml`
Define el Deployment de Kubernetes. Usa la sintaxis `{{ .Values.* }}` para leer los valores de `values.yaml` y `{{ .Release.Name }}` para usar el nombre del release como identificador de los recursos. Incluye:
- `livenessProbe`: si el pod no responde en `http://:80/`, Kubernetes lo reinicia
- `readinessProbe`: el pod no recibe tráfico hasta que responda correctamente
- `volumeMount`: monta el ConfigMap en `/usr/share/nginx/html` para servir la página custom
- Límites de CPU y memoria definidos en `values.yaml`

#### `templates/service.yaml`
Crea el Service de tipo ClusterIP que expone los pods dentro del cluster en el puerto 80. Es el recurso que el Ingress usa como backend para enrutar el tráfico entrante hacia los pods de nginx.

#### `templates/ingress.yaml`
Crea el Ingress que expone la app hacia afuera del cluster. Configura NGINX como ingress class y enruta el tráfico hacia `nginx.local/` al Service de nginx. Hace accesible la app desde el navegador en `http://nginx.local`.

#### `templates/pdb.yaml`
Crea el PodDisruptionBudget con `minAvailable: 1`. Garantiza que durante operaciones de mantenimiento (como un `kubectl drain` de un nodo o un rolling update) Kubernetes nunca baje todos los pods al mismo tiempo. Siempre queda al menos uno disponible para servir tráfico.

#### `templates/configmap.yaml`
Almacena una página HTML custom que nginx sirve como página de inicio. El contenido se monta en el Deployment como volumen en `/usr/share/nginx/html`, reemplazando la página por defecto de nginx. Al ser un ConfigMap, el HTML puede modificarse haciendo un commit al repo sin necesidad de reconstruir la imagen Docker. No contiene datos sensibles por lo que es seguro versionarlo en Git.

### Descripción de cada archivo del chart `operators`

#### `Chart.yaml`
Identifica la carpeta `operators/` como un chart Helm de tipo `application`. Es el chart raíz del patrón app-of-apps.

#### `values.yaml`
Define la estructura base con todos los operadores en `enabled: false` y sin versiones. Es el esquema del chart, no los valores reales. Sirve como referencia de qué operadores existen y qué campos son configurables.

#### `minikube-values.yaml`
Los valores reales para el entorno local. Habilita solo `prometheusStack: true` con la versión `93.2.0` y deja el resto en `false`. Es el archivo que ArgoCD usa al renderizar el chart en Minikube, permitiendo activar o desactivar operadores sin tocar el código base.

#### `templates/prometheus-stack.yaml`
Template que genera una Application de ArgoCD (no un recurso de Kubernetes directamente). Cuando ArgoCD renderiza el chart `operators/`, este archivo produce el objeto `Application` llamado `prometheus-stack` que apunta al Helm chart oficial `kube-prometheus-stack` en `https://prometheus-community.github.io/helm-charts`. Esa Application instala Prometheus, el Prometheus Operator y Grafana en el namespace `monitoring` con recursos ajustados para correr en Minikube.

---

## Mejoras de buenas prácticas aplicadas

### Seguridad
- Password de ArgoCD almacenada en un **Secret de Kubernetes** (`argocd-admin-credentials`)
- El provider ArgoCD lee la password del Secret, nunca está hardcodeada en el código

### Resiliencia
- **PodDisruptionBudget** en nginx-app: garantiza al menos 1 pod disponible durante updates o mantenimiento del nodo
- **livenessProbe**: Kubernetes reinicia el pod si no responde en `http://:80/`
- **readinessProbe**: Kubernetes no envía tráfico al pod hasta que esté listo para responder

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
| Día 2 | Helm chart propio en GitHub. Application nginx gestionada desde Terraform. Namespace dedicado con Ingress. Mejoras de buenas prácticas: Secret para password, PodDisruptionBudget, livenessProbe y readinessProbe. Stack de observabilidad con Prometheus + Grafana desplegado via app-of-apps |
