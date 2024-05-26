#!/bin/bash

latency_flag=0
loss_flag=0
latency_threshold=50
loss_threshold=5
ip=192.168.144.47
hostname=$(uname -n)
mtr_id=$(date '+%Y%m%d%H%M%S')
directory='/home/ubuntu'
csv_file="${directory}/Latency-Loss-Connexa-Report.csv"

if [ -n "${directory}" ]; then
    directory=${directory%/}
fi

mtr_report=$(mtr -r -n -c 5 -o AL $ip)

for i in {3..5}; do 
    hop=$(echo "$mtr_report" | sed -n "$i p")
    hop_latency=$(echo "$hop" | awk '{print $3}')
    hop_loss=$(echo "$hop" | awk '{print $NF}' | tr -d '%')
    if [[ -n "${hop_latency}" && $(echo "${hop_latency} > ${latency_threshold}" | bc -l) -eq 1 ]]; then
        latency_flag=1
        break
    fi
    if [[ -n "${hop_loss}" && $(echo "${hop_loss} > ${hop_loss}" | bc -l) -eq 1 ]]; then
        loss_flag=1
        break
    fi
done

csv_data="$hostname,$ip,$latency_flag,$hop_latency,$latency_threshold,$loss_flag,$hop_loss,$loss_threshold"

# Compare the last hop latency and loss with the thresholds
if [[ ${latency_flag} -eq 1 ]] || [[ ${loss_flag} -eq 1 ]]; then
    echo "${mtr_report}" > "${directory}/MTR-${mtr_id}.txt"
    if [ -f "${csv_file}" ]; then
        echo "${csv_data}" >> "${csv_file}"
    else
        echo "HOSTNAME,RESOURCE IP,LATENCY FLAG,HOP LATENCY (ms),LATENCY THRESHOLD (ms),LOSS FLAG,HOP LOSS (%),LOSS THRESHOLD (%),MTR-ID (YYYYMMDDHHMMSS)" > "${csv_file}"
        echo "${csv_data}" >> "${csv_file}"
    fi
fi