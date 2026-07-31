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

{{- define "envpilot-control-plane.image" -}}
{{- $repository := required "image.repository is required" .Values.image.repository -}}
{{- $digest := trim (default "" .Values.image.digest) -}}
{{- if $digest -}}
{{- printf "%s@%s" $repository $digest -}}
{{- else -}}
{{- printf "%s:%s" $repository (include "envpilot-control-plane.imageTag" .) -}}
{{- end -}}
{{- end -}}

{{- define "envpilot-control-plane.imageTag" -}}
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

{{- define "envpilot-control-plane.imagePullPolicy" -}}
{{- $policy := required "image.pullPolicy is required" .Values.image.pullPolicy -}}
{{- if not (has $policy (list "Always" "IfNotPresent" "Never")) -}}
{{- fail "image.pullPolicy must be Always, IfNotPresent, or Never" -}}
{{- end -}}
{{- $policy -}}
{{- end -}}

{{- define "envpilot-control-plane.imageMetadata" -}}
envpilot.io/image-reference: {{ include "envpilot-control-plane.image" . | quote }}
envpilot.io/source-revision: {{ default "" .Values.image.sourceRevision | quote }}
envpilot.io/release: {{ default "" .Values.image.release | quote }}
{{- end -}}

{{- define "envpilot-control-plane.postgresImage" -}}
{{- if .Values.postgres.image.digest -}}
{{- printf "%s@%s" .Values.postgres.image.repository .Values.postgres.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.postgres.image.repository .Values.postgres.image.tag -}}
{{- end -}}
{{- end -}}

{{- define "envpilot-control-plane.redisImage" -}}
{{- if .Values.redis.image.digest -}}
{{- printf "%s@%s" .Values.redis.image.repository .Values.redis.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.redis.image.repository .Values.redis.image.tag -}}
{{- end -}}
{{- end -}}
