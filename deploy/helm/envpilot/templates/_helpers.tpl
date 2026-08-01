{{- define "envpilot.firstStartRegistrationSecretName" -}}
{{- $global := default (dict) .Values.global -}}
{{- $envpilot := default (dict) (get $global "envpilot") -}}
{{- $registration := default (dict) (get $envpilot "firstStartRegistration") -}}
{{- $mode := default "disabled" $registration.mode -}}
{{- if eq $mode "existing" -}}
{{- required "global.envpilot.firstStartRegistration.existingSecret is required when mode=existing" $registration.existingSecret -}}
{{- else -}}
{{- default (printf "%s-first-start-registration" .Release.Name) $registration.secretName -}}
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
