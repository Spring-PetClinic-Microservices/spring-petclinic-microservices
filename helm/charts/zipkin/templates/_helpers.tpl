{{- define "zipkin.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "zipkin.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "zipkin.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{ include "zipkin.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: petclinic
{{- end }}

{{- define "zipkin.selectorLabels" -}}
app.kubernetes.io/name: {{ include "zipkin.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Zipkin uses the upstream openzipkin/zipkin image directly — no global.imageRegistry prefix.
*/}}
{{- define "zipkin.image" -}}
{{- $repo := .Values.image.repository | default "openzipkin/zipkin" }}
{{- $tag := .Values.image.tag | default "latest" }}
{{- printf "%s:%s" $repo $tag }}
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
