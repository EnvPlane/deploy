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

{{- define "envpilot-runner.controlPlaneEndpoint" -}}
{{- $controlPlane := default (dict) .Values.controlPlane -}}
{{- $mode := default "sameCluster" (get $controlPlane "endpointMode") -}}
{{- if eq $mode "remote" -}}
{{- required "controlPlane.url is required when controlPlane.endpointMode=remote" (get $controlPlane "url") -}}
{{- else if eq $mode "sameCluster" -}}
{{- $serviceName := default "envpilot-control-plane" (get $controlPlane "serviceName") -}}
{{- $namespace := default .Release.Namespace (get $controlPlane "namespace") -}}
{{- $port := default 8080 (get $controlPlane "port") -}}
{{- printf "http://%s.%s.svc:%v" $serviceName $namespace $port -}}
{{- else -}}
{{- fail "controlPlane.endpointMode must be sameCluster or remote" -}}
{{- end -}}
{{- end -}}

{{- define "envpilot-runner.managedRemoteEnabled" -}}
{{- $managedRemote := default (dict) .Values.managedRemote -}}
{{- if (get $managedRemote "enabled") }}true{{ else }}false{{ end -}}
{{- end -}}

{{- define "envpilot-runner.managedRemoteMetadata" -}}
{{- $managedRemote := default (dict) .Values.managedRemote -}}
{{- if (get $managedRemote "enabled") }}
envpilot.io/managed-remote: "true"
envpilot.io/remote-cluster-id: {{ get $managedRemote "remoteClusterId" | quote }}
envpilot.io/project-id: {{ get $managedRemote "projectId" | quote }}
envpilot.io/auth-revision: {{ get $managedRemote "authRevision" | quote }}
envpilot.io/auth-rotation: {{ default "" (get $managedRemote "authRotation") | quote }}
{{- end }}
{{- end -}}

{{- define "envpilot-runner.validateManagedRemote" -}}
{{- $managedRemote := default (dict) .Values.managedRemote -}}
{{- if (get $managedRemote "enabled") -}}
{{- $controlPlane := default (dict) .Values.controlPlane -}}
{{- $url := default "" (get $controlPlane "url") -}}
{{- $endpointMode := default "sameCluster" (get $controlPlane "endpointMode") -}}
{{- $targetNamespaces := default (list) (get $managedRemote "targetNamespaces") -}}
{{- $writer := default (dict) .Values.rbac.featureEnvWriter -}}
{{- $writerMode := default "releaseNamespace" (get $writer "mode") -}}
{{- $writerNamespaces := default (list) (get $writer "namespaces") -}}
{{- $generatedNamespaces := default (list) (get $writer "generatedNamespaces") -}}
{{- if ne $endpointMode "remote" }}{{ fail "managedRemote.enabled requires controlPlane.endpointMode=remote" }}{{ end -}}
{{- if not $url }}{{ fail "managedRemote.enabled requires an explicit controlPlane.url" }}{{ end -}}
{{- if not (regexMatch "^https://" $url) }}{{ fail "managedRemote.enabled requires an https:// controlPlane.url" }}{{ end -}}
{{- $urlLower := lower $url -}}
{{- if regexMatch "^https://(localhost|127\\.[0-9.]+|\\[::1\\]|host\\.minikube\\.internal)([:/]|$)" $urlLower }}{{ fail "managedRemote.enabled rejects host-local controlPlane.url values" }}{{ end -}}
{{- if or (contains ".svc/" $urlLower) (contains ".svc:" $urlLower) (contains ".svc." $urlLower) (hasSuffix ".svc" $urlLower) }}{{ fail "managedRemote.enabled rejects Kubernetes Service DNS controlPlane.url values; use a target-pod-reachable external HTTPS endpoint" }}{{ end -}}
{{- if not (get $controlPlane "existingSecret") }}{{ fail "managedRemote.enabled requires controlPlane.existingSecret" }}{{ end -}}
{{- if or (get $controlPlane "token") (get $controlPlane "configToken") (get $controlPlane "allowUnsafePlaintextTokens") }}{{ fail "managedRemote.enabled requires Secret-referenced bootstrap auth and rejects plaintext tokens" }}{{ end -}}
{{- if not (get $managedRemote "remoteClusterId") }}{{ fail "managedRemote.enabled requires managedRemote.remoteClusterId" }}{{ end -}}
{{- if not (get $managedRemote "projectId") }}{{ fail "managedRemote.enabled requires managedRemote.projectId" }}{{ end -}}
{{- if not (get $managedRemote "authRevision") }}{{ fail "managedRemote.enabled requires managedRemote.authRevision" }}{{ end -}}
{{- if not .Values.rbac.create }}{{ fail "managedRemote.enabled requires rbac.create=true so target namespace RBAC can be reconciled" }}{{ end -}}
{{- if ne (default "cluster" .Values.rbac.discovery.scope) "namespace" }}{{ fail "managedRemote.enabled requires rbac.discovery.scope=namespace" }}{{ end -}}
{{- if not (default "" .Values.rbac.discovery.namespace) }}{{ fail "managedRemote.enabled requires rbac.discovery.namespace" }}{{ end -}}
{{- if not $targetNamespaces }}{{ fail "managedRemote.enabled requires managedRemote.targetNamespaces" }}{{ end -}}
{{- if not (has $writerMode (list "preconfiguredNamespaces" "generatedFeatureNamespaces")) }}{{ fail "managedRemote.enabled requires a namespace-scoped featureEnvWriter mode" }}{{ end -}}
{{- if eq $writerMode "preconfiguredNamespaces" }}{{- if ne (join "," $targetNamespaces) (join "," $writerNamespaces) }}{{ fail "managedRemote.targetNamespaces must exactly match rbac.featureEnvWriter.namespaces" }}{{ end }}{{- else if ne (join "," $targetNamespaces) (join "," $generatedNamespaces) }}{{ fail "managedRemote.targetNamespaces must exactly match rbac.featureEnvWriter.generatedNamespaces" }}{{- end -}}
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
