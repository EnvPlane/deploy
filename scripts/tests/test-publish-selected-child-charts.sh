#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"
state="$tmp/state"
mkdir -p "$bin" "$state" "$tmp/charts"

for mapping in \
  envpilot-control-plane:1.0.0 \
  envpilot-frontend:1.0.0 \
  envpilot-agent:1.0.0 \
  envpilot-runner:9.9.9 \
  envpilot-webhook:1.0.0 \
  envpilot-e2e-workload:1.0.0; do
  chart="${mapping%%:*}"
  version="${mapping##*:}"
  mkdir -p "$tmp/charts/$chart"
  printf 'apiVersion: v2\nname: %s\nversion: %s\n' "$chart" "$version" > "$tmp/charts/$chart/Chart.yaml"
done

cat > "$tmp/Chart.yaml" <<'EOF'
apiVersion: v2
name: envpilot
version: 1.0.0
dependencies:
  - name: envpilot-control-plane
    version: 1.0.0
  - name: envpilot-frontend
    version: 1.0.0
  - name: envpilot-agent
    version: 1.0.0
  - name: envpilot-runner
    version: 9.9.9
  - name: envpilot-webhook
    version: 1.0.0
  - name: envpilot-e2e-workload
    version: 1.0.0
EOF

cat > "$bin/helm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  dependency|lint) exit 0 ;;
  package)
    chart_dir="$2"
    shift 2
    [[ "$1" == "--destination" ]]
    destination="$2"
    chart="$(awk '/^name:/{print $2; exit}' "$chart_dir/Chart.yaml")"
    version="$(awk '/^version:/{print $2; exit}' "$chart_dir/Chart.yaml")"
    : > "$destination/$chart-$version.tgz"
    ;;
  push)
    package="$2"
    chart="$(basename "$package" | sed -E 's/-[0-9]+\.[0-9]+\.[0-9]+\.tgz$//')"
    touch "$FAKE_STATE/$chart.published"
    printf 'Pushed: ghcr.io/envpilot/%s\nDigest: sha256:%064d\n' "$chart" 9
    ;;
  show)
    ref="$3"
    chart_and_version="${ref##*/}"
    chart="${chart_and_version%:*}"
    version="${chart_and_version##*:}"
    if [[ "$chart" == envpilot-runner && ! -f "$FAKE_STATE/$chart.published" ]]; then
      echo 'manifest unknown' >&2
      exit 1
    fi
    printf 'name: %s\nversion: %s\n' "$chart" "$version"
    ;;
  *) echo "unexpected helm command: $*" >&2; exit 2 ;;
esac
EOF

cat > "$bin/oras" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1 $2 $3" == "manifest fetch --descriptor" ]] || { echo "unexpected oras command: $*" >&2; exit 2; }
chart_and_version="${4##*/}"
chart="${chart_and_version%:*}"
if [[ "$chart" == envpilot-runner && ! -f "$FAKE_STATE/$chart.published" ]]; then
  echo 'manifest unknown' >&2
  exit 1
fi
if [[ "$chart" == envpilot-runner ]]; then
  printf '{"digest":"sha256:%064d"}\n' 9
else
  printf '{"digest":"sha256:%064d"}\n' 1
fi
EOF

cat > "$bin/cosign" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_STATE/cosign.calls"
EOF
chmod +x "$bin/helm" "$bin/oras" "$bin/cosign"

PATH="$bin:$PATH" FAKE_STATE="$state" "$root/scripts/publish-selected-child-charts.sh" \
  --umbrella-chart "$tmp/Chart.yaml" \
  --charts-dir "$tmp/charts" \
  --dist "$tmp/dist" \
  --output "$tmp/selected.json" \
  --owner envpilot \
  --source-revision 0123456789abcdef0123456789abcdef01234567 >/dev/null

jq -e '
  .schemaVersion == 1 and (.childCharts | length == 6) and
  ([.childCharts[] | select(.component == "runner")][0] |
    .chart == "envpilot-runner" and .version == "9.9.9" and
    .publication == "published" and (.digest | test("^sha256:[0-9]{63}9$")))
' "$tmp/selected.json" >/dev/null
grep -Fq 'sign --yes ghcr.io/envpilot/envpilot-runner@sha256:' "$state/cosign.calls"
grep -Fq 'attest --yes --predicate' "$state/cosign.calls"

perl -0pi -e 's/(name: envpilot-runner\n    version: )9\.9\.9/${1}9.9.10/' "$tmp/Chart.yaml"
if PATH="$bin:$PATH" FAKE_STATE="$state" "$root/scripts/publish-selected-child-charts.sh" \
  --umbrella-chart "$tmp/Chart.yaml" \
  --charts-dir "$tmp/charts" \
  --dist "$tmp/mismatch-dist" \
  --output "$tmp/mismatch.json" \
  --owner envpilot \
  --source-revision 0123456789abcdef0123456789abcdef01234567 >"$tmp/mismatch.log" 2>&1; then
  echo "mismatched umbrella dependency unexpectedly reached chart publication" >&2
  exit 1
fi
grep -Fq 'umbrella selects envpilot-runner:9.9.10 but canonical child is 9.9.9' "$tmp/mismatch.log"

echo "selected child-chart publication regression is valid"
