{{- define "envplane-runner.name" -}}
{{- default (default .Chart.Name .Values.nameOverride) .Values.legacyChartName | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "envplane-runner.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "envplane-runner.name" . -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "envplane-runner.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "envplane-runner.labels" -}}
helm.sh/chart: {{ include "envplane-runner.chart" . }}
app.kubernetes.io/name: {{ include "envplane-runner.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "envplane-runner.selectorLabels" -}}
app.kubernetes.io/name: {{ include "envplane-runner.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "envplane-runner.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "envplane-runner.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "envplane-runner.tokenSecretName" -}}
{{- $global := default (dict) .Values.global -}}
{{- $envplane := include "envplane-runner.globalConfig" . | fromJson -}}
{{- $firstStart := default (dict) (get $envplane "firstStartRegistration") -}}
{{- $mode := default "disabled" $firstStart.mode -}}
{{- if eq $mode "existing" -}}
{{- required "global.envplane.firstStartRegistration.existingSecret is required when mode=existing" $firstStart.existingSecret -}}
{{- else if eq $mode "managed" -}}
{{- default (printf "%s-first-start-registration" .Release.Name) $firstStart.secretName -}}
{{- else if .Values.controlPlane.existingSecret -}}
{{- .Values.controlPlane.existingSecret -}}
{{- else -}}
{{- printf "%s-token" (include "envplane-runner.fullname" .) -}}
{{- end -}}
{{- end -}}

{{- define "envplane-runner.controlPlaneEndpoint" -}}
{{- $controlPlane := default (dict) .Values.controlPlane -}}
{{- $mode := default "sameCluster" (get $controlPlane "endpointMode") -}}
{{- if eq $mode "remote" -}}
{{- $url := required "controlPlane.url is required when controlPlane.endpointMode=remote" (get $controlPlane "url") -}}
{{- $urlLower := lower $url -}}
{{- if not (regexMatch "^https://[^/?#]+(/[^?#]*)?$" $url) }}{{ fail "controlPlane.url must be an explicit stable https:// endpoint when controlPlane.endpointMode=remote" }}{{ end -}}
{{- if or (contains "@" $url) (contains "?" $url) (contains "#" $url) }}{{ fail "controlPlane.url must not include credentials, query parameters, or fragments" }}{{ end -}}
{{- if regexMatch "^https://(localhost|127\\.[0-9.]+|\\[::1\\]|host\\.minikube\\.internal|envplane\\.local)([:/]|$)" $urlLower }}{{ fail "controlPlane.endpointMode=remote rejects host-local and port-forward controlPlane.url values" }}{{ end -}}
{{- if or (contains ".svc/" $urlLower) (contains ".svc:" $urlLower) (contains ".svc." $urlLower) (hasSuffix ".svc" $urlLower) }}{{ fail "controlPlane.endpointMode=remote rejects Kubernetes Service DNS controlPlane.url values; use a target-pod-reachable private or public HTTPS endpoint" }}{{ end -}}
{{- $tls := default (dict) (get $controlPlane "tls") -}}
{{- if and (get $tls "caSecret") (not (get $tls "caKey")) }}{{ fail "controlPlane.tls.caKey is required when controlPlane.tls.caSecret is set" }}{{ end -}}
{{- $url -}}
{{- else if eq $mode "sameCluster" -}}
{{- $serviceName := default "envplane-control-plane" (get $controlPlane "serviceName") -}}
{{- $namespace := default .Release.Namespace (get $controlPlane "namespace") -}}
{{- $port := default 8080 (get $controlPlane "port") -}}
{{- printf "http://%s.%s.svc:%v" $serviceName $namespace $port -}}
{{- else -}}
{{- fail "controlPlane.endpointMode must be sameCluster or remote" -}}
{{- end -}}
{{- end -}}

{{- define "envplane-runner.managedRemoteEnabled" -}}
{{- $managedRemote := default (dict) .Values.managedRemote -}}
{{- if (get $managedRemote "enabled") }}true{{ else }}false{{ end -}}
{{- end -}}

{{- define "envplane-runner.managedRemoteMetadata" -}}
{{- $managedRemote := default (dict) .Values.managedRemote -}}
{{- if (get $managedRemote "enabled") }}
envplane.io/managed-remote: "true"
envplane.io/remote-cluster-id: {{ get $managedRemote "remoteClusterId" | quote }}
envplane.io/project-id: {{ get $managedRemote "projectId" | quote }}
envplane.io/auth-revision: {{ get $managedRemote "authRevision" | quote }}
envplane.io/auth-rotation: {{ default "" (get $managedRemote "authRotation") | quote }}
envplane.io/compatibility-pin: {{ default "" (get $managedRemote "compatibilityPin") | quote }}
envplane.io/generation: {{ default 0 (get $managedRemote "generation") | quote }}
envplane.io/management-endpoint-profile-generation: {{ default 0 (get $managedRemote "managementEndpointProfileGeneration") | quote }}
envplane.io/trust-revision: {{ default "" (get $managedRemote "trustRevision") | quote }}
envplane.io/legacy-migration: {{ default false (get $managedRemote "allowLegacyMigration") | quote }}
{{- end }}
{{- end -}}

{{- define "envplane-runner.validateManagedRemote" -}}
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
{{- if or (contains ".svc/" $urlLower) (contains ".svc:" $urlLower) (contains ".svc." $urlLower) (hasSuffix ".svc" $urlLower) }}{{ fail "managedRemote.enabled rejects Kubernetes Service DNS controlPlane.url values; use a target-pod-reachable private or public HTTPS endpoint" }}{{ end -}}
{{- if not (get $controlPlane "existingSecret") }}{{ fail "managedRemote.enabled requires controlPlane.existingSecret" }}{{ end -}}
{{- if or (get $controlPlane "token") (get $controlPlane "configToken") (get $controlPlane "allowUnsafePlaintextTokens") }}{{ fail "managedRemote.enabled requires Secret-referenced bootstrap auth and rejects plaintext tokens" }}{{ end -}}
{{- if not (get $managedRemote "remoteClusterId") }}{{ fail "managedRemote.enabled requires managedRemote.remoteClusterId" }}{{ end -}}
{{- if not (get $managedRemote "projectId") }}{{ fail "managedRemote.enabled requires managedRemote.projectId" }}{{ end -}}
{{- if not (get $managedRemote "authRevision") }}{{ fail "managedRemote.enabled requires managedRemote.authRevision" }}{{ end -}}
{{- if not (regexMatch "^sha256:[a-f0-9]{64}$" (default "" (get $managedRemote "compatibilityPin"))) }}{{ fail "managedRemote.enabled requires an immutable managedRemote.compatibilityPin" }}{{ end -}}
{{- if lt (int (default 0 (get $managedRemote "generation"))) 1 }}{{ fail "managedRemote.enabled requires managedRemote.generation greater than zero" }}{{ end -}}
{{- if not .Values.rbac.create }}{{ fail "managedRemote.enabled requires rbac.create=true so target namespace RBAC can be reconciled" }}{{ end -}}
{{- if ne (default "cluster" .Values.rbac.discovery.scope) "namespace" }}{{ fail "managedRemote.enabled requires rbac.discovery.scope=namespace" }}{{ end -}}
{{- if not (default "" .Values.rbac.discovery.namespace) }}{{ fail "managedRemote.enabled requires rbac.discovery.namespace" }}{{ end -}}
{{- $writerEnabled := default false (get $writer "enabled") -}}
{{- if not $targetNamespaces -}}
  {{- if $writerEnabled }}{{ fail "managedRemote with no targetNamespaces must disable featureEnvWriter rather than broadening RBAC" }}{{ end -}}
{{- else -}}
  {{- if not $writerEnabled }}{{ fail "managedRemote targetNamespaces require featureEnvWriter.enabled=true" }}{{ end -}}
  {{- if not (has $writerMode (list "preconfiguredNamespaces" "generatedFeatureNamespaces")) }}{{ fail "managedRemote.enabled requires a namespace-scoped featureEnvWriter mode" }}{{ end -}}
  {{- if eq $writerMode "preconfiguredNamespaces" }}{{- if ne (join "," $targetNamespaces) (join "," $writerNamespaces) }}{{ fail "managedRemote.targetNamespaces must exactly match rbac.featureEnvWriter.namespaces" }}{{ end }}{{- else if ne (join "," $targetNamespaces) (join "," $generatedNamespaces) }}{{ fail "managedRemote.targetNamespaces must exactly match rbac.featureEnvWriter.generatedNamespaces" }}{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "envplane-runner.usesFirstStartRegistration" -}}
{{- $global := default (dict) .Values.global -}}
{{- $envplane := include "envplane-runner.globalConfig" . | fromJson -}}
{{- $firstStart := default (dict) (get $envplane "firstStartRegistration") -}}
{{- $managedSameCluster := default (dict) .Values.managedSameCluster -}}
{{- if and (not (default false $managedSameCluster.enabled)) (ne (default "disabled" $firstStart.mode) "disabled") }}true{{ else }}false{{ end -}}
{{- end -}}

{{- define "envplane-runner.image" -}}
{{- $repository := required "image.repository is required" .Values.image.repository -}}
{{- $digest := trim (default "" .Values.image.digest) -}}
{{- if $digest -}}
{{- printf "%s@%s" $repository $digest -}}
{{- else -}}
{{- printf "%s:%s" $repository (include "envplane-runner.imageTag" .) -}}
{{- end -}}
{{- end -}}

{{- define "envplane-runner.imageTag" -}}
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

{{- define "envplane-runner.imagePullPolicy" -}}
{{- $policy := required "image.pullPolicy is required" .Values.image.pullPolicy -}}
{{- if not (has $policy (list "Always" "IfNotPresent" "Never")) -}}
{{- fail "image.pullPolicy must be Always, IfNotPresent, or Never" -}}
{{- end -}}
{{- $policy -}}
{{- end -}}

{{- define "envplane-runner.imagePullSecrets" -}}
{{- $explicit := default (list) .Values.imagePullSecrets -}}
{{- $global := default (dict) .Values.global -}}
{{- $envplane := include "envplane-runner.globalConfig" . | fromJson -}}
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

{{- define "envplane-runner.imageMetadata" -}}
envplane.io/image-reference: {{ include "envplane-runner.image" . | quote }}
envplane.io/source-revision: {{ default "" .Values.image.sourceRevision | quote }}
envplane.io/release: {{ default "" .Values.image.release | quote }}
{{- end -}}
{{- define "envplane-runner.globalConfig" -}}
{{- $global := default (dict) .Values.global -}}
{{- $legacy := deepCopy (default (dict) (get $global "envplane")) -}}
{{- $canonical := default (dict) (get $global "envplane") -}}
{{- toJson (mergeOverwrite $legacy $canonical) -}}
{{- end -}}
