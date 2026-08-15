{{/*
Return the effective global product configuration. `global.envplane` is the
canonical spelling; `global.envpilot` remains a compatibility source. A
recursive overwrite makes canonical values win without renaming any live
Kubernetes objects or selectors.
*/}}
{{- define "envpilot.globalConfig" -}}
{{- $global := default (dict) .Values.global -}}
{{- $legacy := deepCopy (default (dict) (get $global "envpilot")) -}}
{{- $canonical := default (dict) (get $global "envplane") -}}
{{- toJson (mergeOverwrite $legacy $canonical) -}}
{{- end -}}

{{- define "envpilot.firstStartRegistrationSecretName" -}}
{{- $global := default (dict) .Values.global -}}
{{- $envpilot := include "envpilot.globalConfig" . | fromJson -}}
{{- $registration := default (dict) (get $envpilot "firstStartRegistration") -}}
{{- $mode := default "disabled" $registration.mode -}}
{{- if eq $mode "existing" -}}
{{- required "global.envpilot.firstStartRegistration.existingSecret is required when mode=existing" $registration.existingSecret -}}
{{- else -}}
{{- default (printf "%s-first-start-registration" .Release.Name) $registration.secretName -}}
{{- end -}}
{{- end -}}

{{/*
Return the de-duplicated image pull Secret list shared by every child chart.
Only Secret names are rendered; the Secret data is managed by the operator.
*/}}
{{- define "envpilot.registryImagePullSecrets" -}}
{{- $envpilot := include "envpilot.globalConfig" . | fromJson -}}
{{- $registry := default (dict) (get $envpilot "registry") -}}
{{- $items := default (list) $registry.imagePullSecrets -}}
{{- $existing := default "" $registry.existingSecret -}}
{{- $seen := dict -}}
{{- $result := list -}}
{{- range $item := $items }}
  {{- $name := default "" $item.name -}}
  {{- if and $name (not (hasKey $seen $name)) }}
    {{- $_ := set $seen $name true -}}
    {{- $result = append $result (dict "name" $name) -}}
  {{- end }}
{{- end }}
{{- if and $existing (not (hasKey $seen $existing)) }}
  {{- $result = append $result (dict "name" $existing) -}}
{{- end }}
{{- if gt (len $result) 0 }}{{ toYaml $result }}{{- end }}
{{- end -}}

{{/*
Return the platform dependency contract after applying the explicit public
access profile. `access.mode=ingress` with className=nginx is a complete,
opt-in request for ingress-nginx: detect and reuse a healthy existing class,
or let the reconciler install the pinned provider. Other controller classes
must declare their provider explicitly under platformDependencies.ingress.
*/}}
{{- define "envpilot.effectivePlatformDependencies" -}}
{{- $dependencies := deepCopy (default (dict) .Values.platformDependencies) -}}
{{- $ingress := deepCopy (default (dict) (get $dependencies "ingress")) -}}
{{- $access := default (dict) .Values.access -}}
{{- $accessIngress := default (dict) (get $access "ingress") -}}
{{- $accessMode := default "disabled" (get $access "mode") -}}
{{- $className := default "" (get $accessIngress "className") -}}
{{- $configuredMode := default "disabled" (get $ingress "mode") -}}
{{- $autoAccess := and (eq $accessMode "ingress") (eq $configuredMode "disabled") (eq $className "nginx") -}}
{{- if $autoAccess -}}
  {{- $smoke := dict "serviceName" (default "envpilot-frontend" (get (default (dict) (get $access "services")) "frontendName")) "namespace" .Release.Namespace "port" 3000 "host" (default "" (get $accessIngress "host")) -}}
  {{- $controllerValues := dict "controller" (dict "ingressClassResource" (dict "name" $className "enabled" true "default" false) "service" (dict "type" "LoadBalancer")) -}}
  {{- $managed := dict "chartRef" "https://github.com/kubernetes/ingress-nginx/releases/download/helm-chart-4.11.0/ingress-nginx-4.11.0.tgz" "chartSha256" "eac211cdd9a5ae960f9c319e88c81d4e6e1ba5339599e217229d907bc9f67737" "version" "4.11.0" "releaseName" (printf "%s-ingress-nginx" .Release.Name) "namespace" "ingress-nginx" "cleanupPolicy" "retain" "values" $controllerValues "smoke" $smoke -}}
  {{- $_ := set $ingress "mode" "auto" -}}
  {{- $_ := set $ingress "provider" "nginx" -}}
  {{- $_ := set $ingress "existingClassName" $className -}}
  {{- $_ := set $ingress "namespace" "ingress-nginx" -}}
  {{- $_ := set $ingress "version" "4.11.0" -}}
  {{- $_ := set $ingress "managed" $managed -}}
  {{- $_ := set $dependencies "ingress" $ingress -}}
{{- end -}}
{{- if and (eq (default "" $ingress.provider) "nginx") (or (eq (default "disabled" $ingress.mode) "auto") (eq (default "disabled" $ingress.mode) "managed")) -}}
  {{- if empty $ingress.namespace }}{{- $_ := set $ingress "namespace" "ingress-nginx" -}}{{- end -}}
  {{- $managed := deepCopy (default (dict) $ingress.managed) -}}
  {{- if empty $managed.namespace }}{{- $_ := set $managed "namespace" $ingress.namespace -}}{{- end -}}
  {{- $_ := set $ingress "managed" $managed -}}
  {{- $_ := set $dependencies "ingress" $ingress -}}
{{- end -}}
{{- toJson $dependencies -}}
{{- end -}}

{{/*
The reconciler is opt-in. Merely installing the umbrella chart must not pull a
private optional image when no external platform provider is configured.
*/}}
{{- define "envpilot.platformReconcilerEnabled" -}}
{{- $requested := default false .Values.platformDependencyReconciler.enabled -}}
{{- $dependencies := include "envpilot.effectivePlatformDependencies" . | fromJson -}}
{{- $access := default (dict) .Values.access -}}
{{- $accessIngress := default (dict) (get $access "ingress") -}}
{{- $autoAccess := and (eq (default "disabled" (get $access "mode")) "ingress") (eq (default "" (get $accessIngress "className")) "nginx") (eq (default "disabled" (get (default (dict) (get .Values.platformDependencies "ingress")) "mode")) "disabled") -}}
{{- if and (not $requested) $autoAccess }}
  {{- $requested = true -}}
{{- end -}}
{{- if not $requested -}}false{{- else -}}
  {{- $configured := false -}}
  {{- range $name := list "ingress" "dns" "storage" -}}
    {{- $dependency := index $dependencies $name -}}
    {{- if ne (default "disabled" $dependency.mode) "disabled" }}{{- $configured = true -}}{{- end -}}
  {{- end -}}
  {{- if not $configured -}}false{{- else -}}
    {{- $registry := default (dict) (get (include "envpilot.globalConfig" $ | fromJson) "registry") -}}
    {{- $explicitPullSecrets := default (list) $.Values.platformDependencyReconciler.imagePullSecrets -}}
    {{- if and (ne (default "disabled" $registry.mode) "existing") (eq (len $explicitPullSecrets) 0) -}}
      {{- fail "platformDependencyReconciler requires global.envpilot.registry.mode=existing with existingSecret, or platformDependencyReconciler.imagePullSecrets" -}}
    {{- end -}}
    true
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
The observed status payload is written by the platform reconciler after Helm
has installed the release. Scope its ConfigMap to the Helm revision so the next
server-side upgrade creates a fresh object instead of applying over a
controller-owned data.status.json field. An explicit name is external and must
be supplied/owned by the operator.
*/}}
{{- define "envpilot.platformReconcilerStatusConfigMapName" -}}
{{- $envpilot := include "envpilot.globalConfig" . | fromJson -}}
{{- $status := default (dict) (get $envpilot "platformDependencyStatus") -}}
{{- $override := trim (default "" (get $status "statusConfigMapName")) -}}
{{- if $override -}}
{{- $override -}}
{{- else -}}
{{- printf "%s-platform-dependency-reconciler-status-r%d" .Release.Name .Release.Revision | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Compatibility manifests are intentionally immutable. Revision-scoped names
make the mounted manifest an atomic release input: Helm creates the next map,
switches the control-plane Pod template to it, and then removes the prior
release-owned map. An explicit child-chart name remains an operator-owned
override for advanced integrations.
*/}}
{{- define "envpilot.remoteClusterCompatibilityConfigMapName" -}}
{{- $controlPlane := default (dict) (index .Values "envpilot-control-plane") -}}
{{- $remote := default (dict) (get $controlPlane "remoteClusterReconciler") -}}
{{- $override := trim (default "" (get $remote "compatibilityConfigMapName")) -}}
{{- if $override -}}
{{- $override -}}
{{- else -}}
{{- printf "%s-remote-cluster-compatibility-r%d" .Release.Name .Release.Revision | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Resolve a declared platform dependency state without probing or changing the cluster. */}}
{{- define "envpilot.platformDependencyState" -}}
{{- $dependency := . -}}
{{- $mode := default "disabled" $dependency.mode -}}
{{- if and (or (eq $mode "auto") (eq $mode "managed")) (empty $dependency.provider) -}}
{{- fail (printf "platformDependencies provider is required when mode=%s; configure an explicit provider or use existing/disabled" $mode) -}}
{{- end -}}
{{- if or (eq $mode "auto") (eq $mode "managed") -}}
{{- $managed := default (dict) $dependency.managed -}}
{{- if and (eq $mode "managed") (ne (default "external" $dependency.ownership) "envpilot") -}}{{ fail "platformDependencies ownership must be envpilot when mode=managed" }}{{- end -}}
{{- if empty $managed.chartRef -}}{{ fail "platformDependencies managed.chartRef is required for auto/managed mode" }}{{- end -}}
{{- if empty $managed.version -}}{{ fail "platformDependencies managed.version is required for auto/managed mode" }}{{- end -}}
{{- if empty $managed.releaseName -}}{{ fail "platformDependencies managed.releaseName is required for auto/managed mode" }}{{- end -}}
{{- end -}}
{{- if eq $mode "existing" -}}
{{- $reference := default $dependency.existingClassName $dependency.existingSecret -}}
{{- if empty $reference -}}
{{- fail "platformDependencies existing mode requires existingClassName or existingSecret" -}}
{{- end -}}
{{- end -}}
{{- if $dependency.state -}}
{{- $dependency.state -}}
{{- else if eq $mode "disabled" -}}
disabled
{{- else if eq $mode "existing" -}}
detected
{{- else if eq $mode "managed" -}}
managed
{{- else -}}
missing
{{- end -}}
{{- end -}}
