{{- define "envpilot-agent.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "envpilot-agent.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "envpilot-agent.name" . -}}
{{- end -}}
{{- end -}}

{{- define "envpilot-agent.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "envpilot-agent.labels" -}}
helm.sh/chart: {{ include "envpilot-agent.chart" . }}
app.kubernetes.io/name: {{ include "envpilot-agent.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: cluster-agent
app.kubernetes.io/part-of: envpilot
{{- end -}}

{{- define "envpilot-agent.selectorLabels" -}}
app.kubernetes.io/name: {{ include "envpilot-agent.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: cluster-agent
{{- end -}}

{{- define "envpilot-agent.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "envpilot-agent.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "envpilot-agent.tokenSecretName" -}}
{{- $global := default (dict) .Values.global -}}
{{- $envpilot := default (dict) (get $global "envpilot") -}}
{{- $firstStart := default (dict) (get $envpilot "firstStartRegistration") -}}
{{- $mode := default "disabled" $firstStart.mode -}}
{{- if eq $mode "existing" -}}
{{- required "global.envpilot.firstStartRegistration.existingSecret is required when mode=existing" $firstStart.existingSecret -}}
{{- else if eq $mode "managed" -}}
{{- default (printf "%s-first-start-registration" .Release.Name) $firstStart.secretName -}}
{{- else if .Values.controlPlane.existingSecret -}}
{{- .Values.controlPlane.existingSecret -}}
{{- else -}}
{{- printf "%s-token" (include "envpilot-agent.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "envpilot-agent.usesFirstStartRegistration" -}}
{{- $global := default (dict) .Values.global -}}
{{- $envpilot := default (dict) (get $global "envpilot") -}}
{{- $firstStart := default (dict) (get $envpilot "firstStartRegistration") -}}
{{- if ne (default "disabled" $firstStart.mode) "disabled" }}true{{ else }}false{{ end -}}
{{- end -}}

{{- define "envpilot-agent.image" -}}
{{- $repository := required "image.repository is required" .Values.image.repository -}}
{{- $digest := trim (default "" .Values.image.digest) -}}
{{- if $digest -}}
{{- printf "%s@%s" $repository $digest -}}
{{- else -}}
{{- printf "%s:%s" $repository (include "envpilot-agent.imageTag" .) -}}
{{- end -}}
{{- end -}}

{{- define "envpilot-agent.imageTag" -}}
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

{{- define "envpilot-agent.imagePullPolicy" -}}
{{- $policy := required "image.pullPolicy is required" .Values.image.pullPolicy -}}
{{- if not (has $policy (list "Always" "IfNotPresent" "Never")) -}}
{{- fail "image.pullPolicy must be Always, IfNotPresent, or Never" -}}
{{- end -}}
{{- $policy -}}
{{- end -}}

{{- define "envpilot-agent.imageMetadata" -}}
envpilot.io/image-reference: {{ include "envpilot-agent.image" . | quote }}
envpilot.io/source-revision: {{ default "" .Values.image.sourceRevision | quote }}
envpilot.io/release: {{ default "" .Values.image.release | quote }}
{{- end -}}
