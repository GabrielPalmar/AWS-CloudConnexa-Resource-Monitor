#!/bin/bash

LOCKFILE="/tmp/mtr_script_lock"

# Lockfile process
if [ -e "${LOCKFILE}" ]; then
    echo "Script is already running."
    exit 1
else
    touch "${LOCKFILE}"
fi

trap 'rm -f "${LOCKFILE}"; exit' INT TERM EXIT

# Assign command-line arguments to variables
LATENCY_THRESHOLD=${1}
LOSS_THRESHOLD=${2}
DIRECTORY=${3}

# Arguments check
if [ "${#}" -lt 3 ]; then
    echo "Usage: ${0} <latency_threshold> <loss_threshold> <report_directory_path>"
    exit 1
fi

is_number() {
    [[ ${1} =~ ^-?[0-9]+(\.[0-9]+)?$ ]]
}

for arg in "${1}" "${2}"; do
    if ! is_number "${arg}"; then
        echo "Error: Argument '${arg}' is not a number."
        exit 1
    fi
done

if [ -n "${DIRECTORY}" ]; then
    DIRECTORY=${DIRECTORY%/}
fi

if [[ -n "${DIRECTORY}" && ! -d "${DIRECTORY}" ]]; then
    echo "Error: Directory '${DIRECTORY}' does not exist."
    exit 1
fi

# Extract the gateway IP and check if it's IPv6
GATEWAY_IP=$(ss -nn | grep '1194' | awk '{split($6, a, ":"); print a[1]}')

if (( ${#GATEWAY_IP} < 6 )); then
    GATEWAY_IP=$(ss -nn | grep '1194' | awk '{split($6, a, "]"); print a[1]}' | tr -d '[')
fi

# Generate the MTR report for the gateway IP
MTR_REPORT=$(mtr -r -n -c 25 -o AL ${GATEWAY_IP})

# Parse the last hop latency and loss from the MTR report
LAST_HOP_LATENCY=$(echo "${MTR_REPORT}" | tail -n 1 | awk '{print $3}')
LAST_HOP_LOSS=$(echo "${MTR_REPORT}" | tail -n 1 | awk '{print $NF}' | tr -d '%')

# Values for .CSV file
HOSTNAME=$(uname -n)
MTR_ID=$(date '+%Y%m%d%H%M%S')
CSV_FILE="${DIRECTORY}/Latency-Loss-Connexa-Report.csv"

LATENCY_FLAG=0
LOSS_FLAG=0

# Compare the last hop latency with the threshold and set the flag
if (( $(echo "${LAST_HOP_LATENCY} > ${LATENCY_THRESHOLD}" | bc) )); then
    LATENCY_FLAG=1
fi

# Compare the last hop loss with the threshold and set the flag
if (( $(echo "${LAST_HOP_LOSS} > ${LOSS_THRESHOLD}" | bc ) )); then
    LOSS_FLAG=1
fi

CSV_DATA="${HOSTNAME},${GATEWAY_IP},${LATENCY_FLAG},${LAST_HOP_LATENCY},${LATENCY_THRESHOLD},${LOSS_FLAG},${LAST_HOP_LOSS},${LOSS_THRESHOLD},${MTR_ID}"

# Compare the last hop latency and loss with the thresholds
if [[ ${LATENCY_FLAG} -eq 1 ]] || [[ ${LOSS_FLAG} -eq 1 ]]; then
    echo "${MTR_REPORT}" > "${DIRECTORY}/MTR-${MTR_ID}.txt"
    if [ -f "${CSV_FILE}" ]; then
        echo "${CSV_DATA}" >> "${CSV_FILE}"
    else
        echo "HOSTNAME,CLOUDCONNEXA GATEWAY IP,LATENCY FLAG,LAST HOP LATENCY (ms),LATENCY THRESHOLD (ms),LOSS FLAG, LAST HOP LOSS (%),LOSS THRESHOLD (%),MTR-ID (YYYYMMDDHHMMSS)" > "${CSV_FILE}"
        echo "${CSV_DATA}" >> "${CSV_FILE}"
    fi
fi

rm -f "${LOCKFILE}"