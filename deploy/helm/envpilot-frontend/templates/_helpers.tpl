{{- define "envpilot-frontend.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "envpilot-frontend.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "envpilot-frontend.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "envpilot-frontend.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "envpilot-frontend.labels" -}}
helm.sh/chart: {{ include "envpilot-frontend.chart" . }}
app.kubernetes.io/name: {{ include "envpilot-frontend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: frontend
app.kubernetes.io/part-of: envpilot
{{- end -}}

{{- define "envpilot-frontend.selectorLabels" -}}
{{- if .Values.legacyControlPlaneSelector }}
app.kubernetes.io/name: envpilot-control-plane
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: frontend
{{- else }}
app.kubernetes.io/name: {{ include "envpilot-frontend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: frontend
{{- end }}
{{- end -}}

{{- define "envpilot-frontend.image" -}}
{{- $repository := required "image.repository is required" .Values.image.repository -}}
{{- $digest := trim (default "" .Values.image.digest) -}}
{{- if $digest -}}
{{- printf "%s@%s" $repository $digest -}}
{{- else -}}
{{- printf "%s:%s" $repository (include "envpilot-frontend.imageTag" .) -}}
{{- end -}}
{{- end -}}

{{- define "envpilot-frontend.imageTag" -}}
{{- $tag := trim (default "" .Values.image.tag) -}}
{{- $digest := trim (default "" .Values.image.digest) -}}
{{- if and (not $digest) (not $tag) -}}
{{- fail "image.tag is required when image.digest is not set" -}}
{{- end -}}
{{- if eq (lower $tag) "latest" -}}
{{- fail "image.tag must not be latest; use an immutable tag or image.digest" -}}
{{- end -}}
{{- $tag -}}
{{- end -}}

{{- define "envpilot-frontend.imagePullPolicy" -}}
{{- $policy := required "image.pullPolicy is required" .Values.image.pullPolicy -}}
{{- if not (has $policy (list "Always" "IfNotPresent" "Never")) -}}
{{- fail "image.pullPolicy must be Always, IfNotPresent, or Never" -}}
{{- end -}}
{{- $policy -}}
{{- end -}}

{{- define "envpilot-frontend.imageMetadata" -}}
envpilot.io/image-reference: {{ include "envpilot-frontend.image" . | quote }}
envpilot.io/source-revision: {{ default "" .Values.image.sourceRevision | quote }}
envpilot.io/release: {{ default "" .Values.image.release | quote }}
{{- end -}}
