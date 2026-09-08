#!/usr/bin/env bash
set -euo pipefail

if (($# == 0)); then
	mapfile -t chart_dirs < <(
		find deploy/helm -type f -path '*/templates/deployment.yaml' -print \
			| sed 's#/templates/deployment.yaml$##' \
			| sort -u
	)
else
	chart_dirs=("$@")
fi

if ((${#chart_dirs[@]} == 0)); then
	echo "no deployment charts found" >&2
	exit 1
fi

for chart_dir in "${chart_dirs[@]}"; do
	if [[ ! -f "$chart_dir/Chart.yaml" ]]; then
		echo "chart not found: $chart_dir" >&2
		exit 2
	fi

	rendered="$(mktemp)"
	trap 'rm -f "$rendered"' EXIT
	helm template probe-port-check "$chart_dir" --set postgres.tls.enabled=false >"$rendered"

	declare -A declared_ports=()
	while IFS=$'\t' read -r deployment container port; do
		[[ -n "$deployment" && -n "$container" && -n "$port" ]] || continue
		declared_ports["$deployment/$container/$port"]=1
	done < <(yq -r '
		select(.kind == "Deployment")
		| .metadata.name as $deployment
		| (.spec.template.spec.containers // [])[]
		| .name as $container
		| (.ports // [])[]
		| [$deployment, $container, (.containerPort | tostring)] | join("\t")
	' "$rendered")
	while IFS=$'\t' read -r deployment container port_name; do
		[[ -n "$deployment" && -n "$container" && -n "$port_name" ]] || continue
		declared_ports["$deployment/$container/$port_name"]=1
	done < <(yq -r '
		select(.kind == "Deployment")
		| .metadata.name as $deployment
		| (.spec.template.spec.containers // [])[]
		| .name as $container
		| (.ports // [])[]
		| select(.name != null)
		| [$deployment, $container, .name] | join("\t")
	' "$rendered")

	while IFS=$'\t' read -r deployment container port; do
		[[ -n "$deployment" && -n "$container" && -n "$port" ]] || continue
		if [[ -z "${declared_ports["$deployment/$container/$port"]:-}" ]]; then
			echo "$chart_dir: $deployment/$container: probe port $port is not declared as a containerPort or port name" >&2
			exit 1
		fi
	done < <(yq -r '
		select(.kind == "Deployment")
		| .metadata.name as $deployment
		| (.spec.template.spec.containers // [])[]
		| .name as $container
		| [
			.livenessProbe.tcpSocket.port,
			.readinessProbe.tcpSocket.port,
			.startupProbe.tcpSocket.port,
			.livenessProbe.httpGet.port,
			.readinessProbe.httpGet.port,
			.startupProbe.httpGet.port
		  ][]
		| select(type != "!!null")
		| [$deployment, $container, (tostring)] | join("\t")
	' "$rendered")

	rm -f "$rendered"
	trap - EXIT
done
