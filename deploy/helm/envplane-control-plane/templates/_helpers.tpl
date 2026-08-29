{{- define "envplane-control-plane.globalConfig" -}}
{{- $global := default (dict) .Values.global -}}
{{- $legacy := deepCopy (default (dict) (get $global "envplane")) -}}
{{- $canonical := default (dict) (get $global "envplane") -}}
{{- toJson (mergeOverwrite $legacy $canonical) -}}
{{- end -}}

{{- define "envplane-control-plane.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "envplane-control-plane.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "envplane-control-plane.name" . -}}
{{- end -}}
{{- end -}}

{{- define "envplane-control-plane.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "envplane-control-plane.labels" -}}
helm.sh/chart: {{ include "envplane-control-plane.chart" . }}
app.kubernetes.io/name: {{ include "envplane-control-plane.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: envplane
{{- end -}}

{{- define "envplane-control-plane.selectorLabels" -}}
app.kubernetes.io/name: {{ include "envplane-control-plane.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: control-plane
{{- end -}}

{{- define "envplane-control-plane.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "envplane-control-plane.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "envplane-control-plane.postgresName" -}}
{{- printf "%s-postgres" (include "envplane-control-plane.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "envplane-control-plane.redisName" -}}
{{- printf "%s-redis" (include "envplane-control-plane.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "envplane-control-plane.authenticationManagedSecretName" -}}
{{- $override := trim (default "" .Values.auth.managedSecret.nameOverride) -}}
{{- if $override -}}
  {{- if or (gt (len $override) 63) (not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" $override)) -}}
    {{- fail "auth.managedSecret.nameOverride must be a Kubernetes DNS label of at most 63 characters" -}}
  {{- end -}}
  {{- $override -}}
{{- else -}}
  {{- printf "%s-authentication" (include "envplane-control-plane.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
The control plane cannot safely persist SCM credentials without this key.
Use a chart-owned Secret by default so a clean install has no hidden manual
prerequisite. Operators may supply an existing Secret when they manage keys
outside Helm.
*/}}
{{- define "envplane-control-plane.credentialEncryptionSecretName" -}}
{{- $existing := trim (default "" .Values.credentialEncryption.existingSecret) -}}
{{- if $existing -}}
{{- $existing -}}
{{- else -}}
{{- printf "%s-runtime-credentials" (include "envplane-control-plane.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "envplane-control-plane.image" -}}
{{- $repository := required "image.repository is required" .Values.image.repository -}}
{{- $digest := trim (default "" .Values.image.digest) -}}
{{- if $digest -}}
{{- printf "%s@%s" $repository $digest -}}
{{- else -}}
{{- printf "%s:%s" $repository (include "envplane-control-plane.imageTag" .) -}}
{{- end -}}
{{- end -}}

{{- define "envplane-control-plane.imageTag" -}}
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

{{- define "envplane-control-plane.imagePullPolicy" -}}
{{- $policy := required "image.pullPolicy is required" .Values.image.pullPolicy -}}
{{- if not (has $policy (list "Always" "IfNotPresent" "Never")) -}}
{{- fail "image.pullPolicy must be Always, IfNotPresent, or Never" -}}
{{- end -}}
{{- $policy -}}
{{- end -}}

{{- define "envplane-control-plane.imagePullSecrets" -}}
{{- $explicit := default (list) .Values.imagePullSecrets -}}
{{- $global := default (dict) .Values.global -}}
{{- $envplane := include "envplane-control-plane.globalConfig" . | fromJson -}}
{{- $registry := default (dict) (get $envplane "registry") -}}
{{- $shared := default (list) $registry.imagePullSecrets -}}
{{- $existing := default "" $registry.existingSecret -}}
{{- $seen := dict -}}
{{- $result := list -}}
{{- range $item := concat $explicit $shared }}
  {{- $name := default "" $item.name -}}
  {{- if and $name (not (hasKey $seen $name)) }}{{- $_ := set $seen $name true -}}{{- $result = append $result (dict "name" $name) -}}{{- end }}
{{- end }}
{{- if and $existing (not (hasKey $seen $existing)) }}{{- $result = append $result (dict "name" $existing) -}}{{- end }}
{{- if gt (len $result) 0 }}{{ toYaml $result }}{{- end }}
{{- end -}}

{{- define "envplane-control-plane.imageMetadata" -}}
envplane.io/image-reference: {{ include "envplane-control-plane.image" . | quote }}
envplane.io/source-revision: {{ default "" .Values.image.sourceRevision | quote }}
envplane.io/release: {{ default "" .Values.image.release | quote }}
{{- end -}}

{{/* Keep in lockstep with the umbrella's revision-scoped observed-status map.
An explicit global name remains an external operator-owned override. */}}
{{- define "envplane-control-plane.platformDependencyStatusConfigMapName" -}}
{{- $global := default (dict) .Values.global -}}
{{- $envplane := include "envplane-control-plane.globalConfig" . | fromJson -}}
{{- $status := default (dict) (get $envplane "platformDependencyStatus") -}}
{{- $override := trim (default "" (get $status "statusConfigMapName")) -}}
{{- if $override -}}
{{- $override -}}
{{- else -}}
{{- printf "%s-platform-dependency-reconciler-status-r%d" .Release.Name .Release.Revision | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Keep in lockstep with the umbrella's immutable release compatibility map. */}}
{{- define "envplane-control-plane.releaseCompatibilityConfigMapName" -}}
{{- printf "%s-release-compatibility-r%d" .Release.Name .Release.Revision | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* The umbrella's immutable compatibility map is revision-scoped so an
upgrade never mutates it in place. */}}
{{- define "envplane-control-plane.remoteClusterCompatibilityConfigMapName" -}}
{{- $override := trim (default "" .Values.remoteClusterReconciler.compatibilityConfigMapName) -}}
{{- if $override -}}
{{- $override -}}
{{- else -}}
{{- printf "%s-remote-cluster-compatibility-r%d" .Release.Name .Release.Revision | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "envplane-control-plane.postgresImage" -}}
{{- if .Values.postgres.image.digest -}}
{{- printf "%s@%s" .Values.postgres.image.repository .Values.postgres.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.postgres.image.repository .Values.postgres.image.tag -}}
{{- end -}}
{{- end -}}

{{- define "envplane-control-plane.redisImage" -}}
{{- if .Values.redis.image.digest -}}
{{- printf "%s@%s" .Values.redis.image.repository .Values.redis.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.redis.image.repository .Values.redis.image.tag -}}
{{- end -}}
{{- end -}}
