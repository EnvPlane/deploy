{{- define "envpilot-webhook.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "envpilot-webhook.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "envpilot-webhook.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "envpilot-webhook.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "envpilot-webhook.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: webhook
app.kubernetes.io/part-of: envpilot
{{- end -}}

{{- define "envpilot-webhook.selectorLabels" -}}
app.kubernetes.io/name: {{ include "envpilot-webhook.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: webhook
{{- end -}}

{{- define "envpilot-webhook.image" -}}
{{- $repository := required "image.repository is required" .Values.image.repository -}}
{{- $digest := trim (default "" .Values.image.digest) -}}
{{- if $digest -}}
{{- printf "%s@%s" $repository $digest -}}
{{- else -}}
{{- $tag := required "image.tag is required when image.digest is empty" .Values.image.tag -}}
{{- if eq (lower $tag) "latest" }}{{ fail "image.tag must be immutable, not latest" }}{{ end -}}
{{- printf "%s:%s" $repository $tag -}}
{{- end -}}
{{- end -}}

{{- define "envpilot-webhook.secretName" -}}
{{- default (include "envpilot-webhook.fullname" .) .Values.secrets.existingSecret -}}
{{- end -}}
