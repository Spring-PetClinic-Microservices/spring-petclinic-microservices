{{- define "visits-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "visits-service.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "visits-service.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{ include "visits-service.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: petclinic
{{- end }}

{{- define "visits-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "visits-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "visits-service.image" -}}
{{- $registry := .Values.global.imageRegistry | default "" }}
{{- $repo := .Values.image.repository | default "spring-petclinic-visits-service" }}
{{- $tag := .Values.image.tag | default .Values.global.imageTag | default "latest" }}
{{- if $registry }}
{{- printf "%s/%s:%s" $registry $repo $tag }}
{{- else }}
{{- printf "%s:%s" $repo $tag }}
{{- end }}
{{- end }}

{{- define "petclinic.initContainers.waitForConfig" -}}
- name: wait-for-config-server
  image: busybox:1.36
  command:
    - sh
    - -c
    - |
      until wget -qO- http://config-server:8888; do
        echo "Waiting for config-server..."
        sleep 5
      done
      echo "config-server is ready"
{{- end }}

{{- define "petclinic.initContainers.waitForDiscovery" -}}
- name: wait-for-discovery-server
  image: busybox:1.36
  command:
    - sh
    - -c
    - |
      until wget -qO- http://discovery-server:8761; do
        echo "Waiting for discovery-server..."
        sleep 5
      done
      echo "discovery-server is ready"
{{- end }}
