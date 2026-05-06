# PetClinic Helm Chart

Umbrella Helm chart for deploying the Spring PetClinic Microservices application to Azure Kubernetes Service (AKS).

## Prerequisites

- Helm ≥ 3.12 installed (`helm version`)
- `kubectl` configured and pointing at your AKS cluster (`kubectl cluster-info`)
- AKS cluster with ACR attached (`az aks update --attach-acr <acr-name> --name <aks-name> --resource-group <rg>`)
- Nginx Ingress Controller deployed in the cluster (Cloud Engineer responsibility)
- Docker images built and pushed to ACR (Container Engineer responsibility)

## Chart Structure

```
helm/
├── Chart.yaml              # Umbrella chart — declares all 11 sub-charts as dependencies
├── values.yaml             # Global defaults and per-service overrides
├── templates/
│   └── namespace.yaml      # Creates the petclinic namespace
└── charts/
    ├── config-server/      # Spring Cloud Config (starts first, no init containers)
    ├── discovery-server/   # Eureka registry (waits for config-server)
    ├── api-gateway/        # Spring Cloud Gateway + Nginx Ingress
    ├── customers-service/
    ├── visits-service/
    ├── vets-service/
    ├── genai-service/      # Includes genai-secret for API keys
    ├── admin-server/       # Spring Boot Admin
    ├── zipkin/             # Distributed tracing
    ├── prometheus/         # Metrics scraping
    └── grafana/            # Metrics dashboards
```

## Startup Order

Kubernetes enforces startup ordering via init containers:

1. **config-server** — starts immediately, no dependencies
2. **discovery-server** — waits for config-server to respond on :8888
3. **All other services** — wait for both config-server (:8888) and discovery-server (:8761)

## Install

### Step 1 — Resolve sub-chart dependencies

```bash
helm dependency update ./helm
```

### Step 2 — Install (minimum required flags)

```bash
helm install petclinic ./helm \
  --namespace petclinic \
  --create-namespace \
  --set global.imageRegistry=<your-acr-name>.azurecr.io \
  --set global.imageTag=latest
```

### Step 3 — Install with GenAI service enabled

Supply the OpenAI or Azure OpenAI credentials at install time. Never commit real keys to values.yaml.

**OpenAI:**
```bash
helm install petclinic ./helm \
  --namespace petclinic \
  --create-namespace \
  --set global.imageRegistry=<your-acr-name>.azurecr.io \
  --set global.imageTag=latest \
  --set genai-service.genaiSecret.openaiApiKey=<your-openai-key>
```

**Azure OpenAI:**
```bash
helm install petclinic ./helm \
  --namespace petclinic \
  --create-namespace \
  --set global.imageRegistry=<your-acr-name>.azurecr.io \
  --set global.imageTag=latest \
  --set genai-service.genaiSecret.azureOpenaiKey=<your-azure-key> \
  --set genai-service.genaiSecret.azureOpenaiEndpoint=https://<your-resource>.openai.azure.com
```

### Step 4 — Install with a custom domain (Ingress host)

```bash
helm install petclinic ./helm \
  --namespace petclinic \
  --create-namespace \
  --set global.imageRegistry=<your-acr-name>.azurecr.io \
  --set api-gateway.ingress.host=petclinic.example.com
```

## Upgrade

```bash
helm upgrade petclinic ./helm \
  --namespace petclinic \
  --set global.imageRegistry=<your-acr-name>.azurecr.io \
  --set global.imageTag=<new-tag>
```

## Uninstall

```bash
helm uninstall petclinic --namespace petclinic
# Optionally remove the namespace
kubectl delete namespace petclinic
```

---

## Validation

### 1 — Wait for all pods to be ready

```bash
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/instance=petclinic \
  -n petclinic \
  --timeout=300s
```

### 2 — Check pod status

```bash
kubectl get pods -n petclinic
```

Expected: all pods in `Running` state with `1/1` or `2/2` READY. No `CrashLoopBackOff` or `ImagePullBackOff`.

### 3 — Check Eureka dashboard (all services registered)

```bash
kubectl port-forward -n petclinic svc/discovery-server 8761:8761
```

Open http://localhost:8761 — you should see all 8 microservices listed as UP.

### 4 — Smoke test the API gateway

```bash
kubectl port-forward -n petclinic svc/api-gateway 8080:8080
```

```bash
# List vets
curl http://localhost:8080/api/vet/vets

# List owners
curl http://localhost:8080/api/customer/owners
```

Both should return HTTP 200 with JSON.

### 5 — Check Grafana dashboards

```bash
kubectl port-forward -n petclinic svc/grafana 3000:3000
```

Open http://localhost:3000 — the Spring PetClinic Metrics dashboard should be pre-loaded.

### 6 — Check Zipkin tracing

```bash
kubectl port-forward -n petclinic svc/zipkin 9411:9411
```

Open http://localhost:9411/zipkin/ — traces appear after making requests through the api-gateway.

---

## Troubleshooting

### Pods stuck in `Init:0/1` or `Init:0/2`

The init containers are waiting for config-server or discovery-server. Check:

```bash
# Check config-server logs
kubectl logs -n petclinic deploy/config-server

# Check init container logs for a stuck pod
kubectl logs -n petclinic <pod-name> -c wait-for-config-server
kubectl logs -n petclinic <pod-name> -c wait-for-discovery-server
```

### Pods in `ImagePullBackOff`

ACR is not attached to the AKS cluster. Run (Cloud Engineer):

```bash
az aks update --attach-acr <acr-name> --name <aks-name> --resource-group <rg>
```

### genai-service in `CrashLoopBackOff`

The API key secret is missing or incorrect. Update it:

```bash
kubectl create secret generic genai-secret \
  --from-literal=OPENAI_API_KEY=<key> \
  --from-literal=AZURE_OPENAI_KEY="" \
  --from-literal=AZURE_OPENAI_ENDPOINT="" \
  -n petclinic \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart the pod to pick up the new secret
kubectl rollout restart deploy/genai-service -n petclinic
```

### Ingress returns 404

Verify the nginx ingress controller is installed and the IngressClass exists:

```bash
kubectl get ingressclass
kubectl get pods -n ingress-nginx
```

---

## Dry-run Validation (no cluster needed)

```bash
# Lint
helm lint ./helm

# Render templates
helm template petclinic ./helm \
  --set global.imageRegistry=test.azurecr.io \
  --namespace petclinic

# Validate against Kubernetes API schemas (requires kubectl)
helm template petclinic ./helm \
  --set global.imageRegistry=test.azurecr.io \
  --namespace petclinic | kubectl apply --dry-run=client -f -
```
