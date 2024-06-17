#!/bin/bash

# Check for dependencies
for pkg in mtr bc python3 python3-pip; do
    if ! command -v $pkg &> /dev/null; then
        sudo apt install $pkg -y &> /dev/null
    fi
done

script_dir='/home/ubuntu/connexa-script.sh'

cat << 'EOF' > $script_dir
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

# Fixed variables
count=25
latency_flag=0
loss_flag=0
latency_threshold=50
loss_threshold=5
ip=192.168.144.47
hostname=$(uname -n)
mtr_id=$(date '+%Y%m%d%H%M%S')
directory='/home/ubuntu/Connexa-Logs'
json_file="$directory/LATENCY-LOSS-CONNEXA-REPORT.json"

# Check target directory
if [[ ! -d "$directory" ]]; then
    mkdir "$directory"
fi

if [[ -n "$directory" && ! -d "$directory" ]]; then
    echo "Error: Directory '$directory' does not exist."
fi

# MTR reports
mtr_report_resource=$(mtr -r -n -c $count -o AL $ip)
line_count=$(echo "$mtr_report_resource" | wc -l)

if [[ $line_count -le 4 ]]; then
    last_line=$line_count
else
    last_line=5
fi

# Check first three hops for latency/loss
for i in $(seq 3 $last_line); do 
    hop=$(echo "$mtr_report_resource" | sed -n "$i p")
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

# Get current CloudConnexa Gateway
path=$(sudo openvpn3 sessions-list | grep -B 3 'CloudConnexa' | grep -o '\S*/net/openvpn/\S*') 
gateway_ip=$(sudo openvpn3-admin journal --path $path | grep 'via' | tail -1 | awk -F '[()]' '{print $2}')

if [[ $latency_flag -eq 1 ]] || [[ $loss_flag -eq 1 ]]; then
    echo "$mtr_report_resource" > "$directory/MTR-RESOURCE-$mtr_id.txt"
    mtr_report_gateway=$(mtr -r -n -c $count -o AL $gateway_ip)
    echo "$mtr_report_gateway" > "$directory/MTR-GATEWAY-$mtr_id.txt"
else
    mtr_id=0
fi

latency=$(ping -q -c $count -n4 $ip | grep 'rtt' | awk -F '/' '{print $5}')

json_data="{\"HOSTNAME\": \"$hostname\",\"RESOURCE_IP\": \"$ip\",\"GATEWAY_IP\": \"$gateway_ip\",\"LATENCY_FLAG\": \"$latency_flag\",\"LATENCY_(ms)\": \"$latency\",\"LATENCY_THRESHOLD_(ms)\": \"$latency_threshold\",\"LOSS_FLAG\": \"$loss_flag\",\"HOP_LOSS_(%)\": \"$hop_loss\",\"LOSS_THRESHOLD_(%)\": \"$loss_threshold\",\"MTR-ID_(YYYYMMDDHHMMSS)\": \"$mtr_id\"}"

if [[ -f "$json_file" ]]; then
    echo "$json_data" >> "$json_file"
else
    echo "$json_data" > "$json_file"
fi

rm -f "$lockfile"
EOF

chmod +x /home/ubuntu/connexa-script.sh

(crontab -l 2>/dev/null; echo "*/1 * * * * $script_dir") | crontab -