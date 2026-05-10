{{- define "envpilot-control-plane.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "envpilot-control-plane.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "envpilot-control-plane.name" . -}}
{{- end -}}
{{- end -}}

{{- define "envpilot-control-plane.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "envpilot-control-plane.labels" -}}
helm.sh/chart: {{ include "envpilot-control-plane.chart" . }}
app.kubernetes.io/name: {{ include "envpilot-control-plane.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: envpilot
{{- end -}}

{{- define "envpilot-control-plane.selectorLabels" -}}
app.kubernetes.io/name: {{ include "envpilot-control-plane.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: control-plane
{{- end -}}

{{- define "envpilot-control-plane.frontendSelectorLabels" -}}
app.kubernetes.io/name: {{ include "envpilot-control-plane.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: frontend
{{- end -}}

{{- define "envpilot-control-plane.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "envpilot-control-plane.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "envpilot-control-plane.postgresName" -}}
{{- printf "%s-postgres" (include "envpilot-control-plane.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "envpilot-control-plane.redisName" -}}
{{- printf "%s-redis" (include "envpilot-control-plane.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
