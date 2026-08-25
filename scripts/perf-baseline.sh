#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT_DIR}/results"
mkdir -p "${RESULTS_DIR}"

PORT="${CMS_PERF_PORT:-4287}"
TOKEN="${CMS_PERF_TOKEN:-stage1-perf-token}"
RUNS="${CMS_PERF_RUNS:-20}"
BASE_URL="http://127.0.0.1:${PORT}"
DB_PATH="${RESULTS_DIR}/perf_${PORT}.db"
LOG_FILE="${RESULTS_DIR}/perf_server.log"
STAMP="$(date +%Y%m%d_%H%M%S)"
REPORT_FILE="${RESULTS_DIR}/perf_baseline_${STAMP}.json"

if [[ -n "${KUJO_BIN:-}" ]]; then
	KUJO_BIN_PATH="${KUJO_BIN}"
elif command -v kujo >/dev/null 2>&1; then
	KUJO_BIN_PATH="$(command -v kujo)"
elif [[ -x "${ROOT_DIR}/../kujo/target/debug/kujo" ]]; then
	KUJO_BIN_PATH="${ROOT_DIR}/../kujo/target/debug/kujo"
else
	echo "Unable to locate Kujo runtime binary. Set KUJO_BIN to continue."
	exit 1
fi

SERVER_PID=""

cleanup() {
	if [[ -n "${SERVER_PID}" ]] && kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
		kill "${SERVER_PID}" >/dev/null 2>&1 || true
		wait "${SERVER_PID}" >/dev/null 2>&1 || true
	fi
	rm -f "${DB_PATH}" "${DB_PATH}-wal" "${DB_PATH}-shm" || true
}
trap cleanup EXIT

json_escape() {
	printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

measure_endpoint() {
	local name="$1"
	local path="$2"
	local auth="${3:-0}"
	local raw_file
	raw_file="$(mktemp)"

	for _ in $(seq 1 "${RUNS}"); do
		if [[ "${auth}" == "1" ]]; then
			curl -sS -o /dev/null -w "%{http_code} %{time_total}\n" -H "Authorization: Bearer ${TOKEN}" "${BASE_URL}${path}" >> "${raw_file}"
		else
			curl -sS -o /dev/null -w "%{http_code} %{time_total}\n" "${BASE_URL}${path}" >> "${raw_file}"
		fi
	done

	local bad_count
	bad_count="$(awk '$1 != 200 {c++} END {print c+0}' "${raw_file}")"
	if [[ "${bad_count}" != "0" ]]; then
		echo "[FAIL] ${name}: non-200 responses detected"
		awk '$1 != 200 {print}' "${raw_file}" | head -n 5
		rm -f "${raw_file}"
		exit 1
	fi

	local stats
	stats="$(awk '
		{times[NR]=$2; sum+=$2}
		END {
			n=NR
			if (n == 0) {
				print "0 0 0 0"
				exit
			}
			for (i=1; i<=n; i++) {
				for (j=i+1; j<=n; j++) {
					if (times[i] > times[j]) {
						t=times[i]; times[i]=times[j]; times[j]=t
					}
				}
			}
			min=times[1]
			max=times[n]
			avg=sum/n
			p95_idx=int((n*95+99)/100)
			if (p95_idx < 1) p95_idx=1
			if (p95_idx > n) p95_idx=n
			p95=times[p95_idx]
			printf "%.6f %.6f %.6f %.6f", min, avg, p95, max
		}
	' "${raw_file}")"

	read -r min avg p95 max <<< "${stats}"
	rm -f "${raw_file}"
	echo "${name}|${path}|${min}|${avg}|${p95}|${max}"
}

echo "Starting CMS API for performance baseline..."
(
	cd "${ROOT_DIR}"
	CMS_API_PORT="${PORT}" \
	CMS_SITE_URL="${BASE_URL}" \
	CMS_DB_PATH="${DB_PATH}" \
	CMS_API_TOKEN="${TOKEN}" \
	"${KUJO_BIN_PATH}" run --interpreter backend/runtime/main.kujo >"${LOG_FILE}" 2>&1
) &
SERVER_PID="$!"

for _ in $(seq 1 60); do
	if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
		echo "Server exited before baseline run."
		tail -n 120 "${LOG_FILE}" || true
		exit 1
	fi
	if curl -sS --max-time 1 "${BASE_URL}/health" >/dev/null 2>&1; then
		break
	fi
	sleep 0.2
done

endpoints=(
	"health|/health|0"
	"capabilities|/v1|0"
	"robots|/robots.txt|0"
	"security-txt|/.well-known/security.txt|0"
	"llms|/llms.txt|0"
	"sitemap|/sitemap.xml|0"
	"rss|/rss.xml|0"
	"entries-list|/v1/entries?limit=10&offset=0|0"
	"media-list|/v1/media?limit=10&offset=0|0"
	"menus-list|/v1/menus?limit=10&offset=0|0"
	"plugins-list|/v1/plugins?limit=10&offset=0|1"
	"themes-list|/v1/themes?limit=10&offset=0|0"
	"roles-list|/v1/auth/roles?limit=10&offset=0|1"
	"tokens-list|/v1/auth/tokens?limit=10&offset=0|1"
)

echo "[Baseline] runs per endpoint: ${RUNS}"
echo "name | path | min_s | avg_s | p95_s | max_s"
echo "-----|------|-------|-------|-------|------"

json_rows=""
first_row=1
for row in "${endpoints[@]}"; do
	name="${row%%|*}"
	rest="${row#*|}"
	path="${rest%%|*}"
	auth="${rest##*|}"
	result="$(measure_endpoint "${name}" "${path}" "${auth}")"

	r_name="${result%%|*}"
	r_rest="${result#*|}"
	r_path="${r_rest%%|*}"
	r_rest="${r_rest#*|}"
	r_min="${r_rest%%|*}"
	r_rest="${r_rest#*|}"
	r_avg="${r_rest%%|*}"
	r_rest="${r_rest#*|}"
	r_p95="${r_rest%%|*}"
	r_max="${r_rest##*|}"

	echo "${r_name} | ${r_path} | ${r_min} | ${r_avg} | ${r_p95} | ${r_max}"

	row_json="{\"name\":\"$(json_escape "${r_name}")\",\"path\":\"$(json_escape "${r_path}")\",\"min_s\":${r_min},\"avg_s\":${r_avg},\"p95_s\":${r_p95},\"max_s\":${r_max}}"
	if [[ "${first_row}" == "1" ]]; then
		json_rows="${row_json}"
		first_row=0
	else
		json_rows="${json_rows},${row_json}"
	fi
done

cat > "${REPORT_FILE}" <<EOF
{
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "runs_per_endpoint": ${RUNS},
  "base_url": "${BASE_URL}",
  "results": [${json_rows}]
}
EOF

cp "${REPORT_FILE}" "${RESULTS_DIR}/perf_baseline_latest.json"
echo "Baseline report: ${REPORT_FILE}"
echo "Latest report: ${RESULTS_DIR}/perf_baseline_latest.json"
