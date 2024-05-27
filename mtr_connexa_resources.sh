#!/bin/bash

# Lockfile process
lockfile="/tmp/mtr_script_lock"

if [ -e "$lockfile" ]; then
    echo "Script is already running."
    exit 1
else
    touch "$lockfile"
fi

trap 'rm -f "$lockfile"; exit' INT TERM EXIT

# Check for dependencies
for pkg in mtr bc python3 python3-pip; do
    if ! command -v $pkg &> /dev/null; then
        sudo apt install $pkg -y &> /dev/null
    fi
done

# Fixed variables
latency_flag=0
loss_flag=0
latency_threshold=50
loss_threshold=5
ip=192.168.144.47
hostname=$(uname -n)
mtr_id=$(date '+%Y%m%d%H%M%S')
directory='/home/ubuntu'
csv_file="$directory/Latency-Loss-Connexa-Report.csv"

if [[ -n "$directory" && ! -d "$directory" ]]; then
    echo "Error: Directory '$directory' does not exist."
    exit 1
fi

mtr_report=$(mtr -r -n -c 5 -o AL $ip)
line_count=$(echo "$mtr_report" | wc -l)

if [[ $line_count -le 4 ]]; then
    last_line=$line_count
else
    last_line=5
fi

for i in $(seq 3 $last_line); do 
    hop=$(echo "$mtr_report" | sed -n "$i p")
    hop_latency=$(echo "$hop" | awk '{print $3}')
    hop_loss=$(echo "$hop" | awk '{print $NF}' | tr -d '%')
    if [[ -n "$hop_latency" && $(echo "$hop_latency > $latency_threshold" | bc -l) -eq 1 ]]; then
        latency_flag=1
    fi
    if [[ -n "$hop_loss" && $(echo "$hop_loss > $loss_threshold" | bc -l) -eq 1 ]]; then
        loss_flag=1
    fi
    if [[ $latency_flag -eq 1 ]] || [[ $loss_flag -eq 1 ]]; then
        break
    fi
done

csv_data="$hostname,$ip,$latency_flag,$hop_latency,$latency_threshold,$loss_flag,$hop_loss,$loss_threshold,$mtr_id"

# Compare the last hop latency and loss with the thresholds
if [[ $latency_flag -eq 1 ]] || [[ $loss_flag -eq 1 ]]; then
    echo "$mtr_report" > "$directory/MTR-$mtr_id.txt"
fi

if [[ -f "$csv_file" ]]; then
    echo "$csv_data" >> "$csv_file"
else
    echo "HOSTNAME,RESOURCE IP,LATENCY FLAG,HOP LATENCY (ms),LATENCY THRESHOLD (ms),LOSS FLAG,HOP LOSS (%),LOSS THRESHOLD (%),MTR-ID (YYYYMMDDHHMMSS)" > "$csv_file"
    echo "$csv_data" >> "$csv_file"
fi

rm -f "$lockfile"