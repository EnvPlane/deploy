{{- define "envpilot-runner.name" -}}
{{- default (default .Chart.Name .Values.nameOverride) .Values.legacyChartName | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "envpilot-runner.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "envpilot-runner.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "envpilot-runner.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "envpilot-runner.labels" -}}
helm.sh/chart: {{ include "envpilot-runner.chart" . }}
app.kubernetes.io/name: {{ include "envpilot-runner.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "envpilot-runner.selectorLabels" -}}
app.kubernetes.io/name: {{ include "envpilot-runner.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "envpilot-runner.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "envpilot-runner.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "envpilot-runner.tokenSecretName" -}}
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
{{- printf "%s-token" (include "envpilot-runner.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "envpilot-runner.usesFirstStartRegistration" -}}
{{- $global := default (dict) .Values.global -}}
{{- $envpilot := default (dict) (get $global "envpilot") -}}
{{- $firstStart := default (dict) (get $envpilot "firstStartRegistration") -}}
{{- if ne (default "disabled" $firstStart.mode) "disabled" }}true{{ else }}false{{ end -}}
{{- end -}}

{{- define "envpilot-runner.image" -}}
{{- $repository := required "image.repository is required" .Values.image.repository -}}
{{- $digest := trim (default "" .Values.image.digest) -}}
{{- if $digest -}}
{{- printf "%s@%s" $repository $digest -}}
{{- else -}}
{{- printf "%s:%s" $repository (include "envpilot-runner.imageTag" .) -}}
{{- end -}}
{{- end -}}

{{- define "envpilot-runner.imageTag" -}}
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

{{- define "envpilot-runner.imagePullPolicy" -}}
{{- $policy := required "image.pullPolicy is required" .Values.image.pullPolicy -}}
{{- if not (has $policy (list "Always" "IfNotPresent" "Never")) -}}
{{- fail "image.pullPolicy must be Always, IfNotPresent, or Never" -}}
{{- end -}}
{{- $policy -}}
{{- end -}}

{{- define "envpilot-runner.imageMetadata" -}}
envpilot.io/image-reference: {{ include "envpilot-runner.image" . | quote }}
envpilot.io/source-revision: {{ default "" .Values.image.sourceRevision | quote }}
envpilot.io/release: {{ default "" .Values.image.release | quote }}
{{- end -}}
