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
