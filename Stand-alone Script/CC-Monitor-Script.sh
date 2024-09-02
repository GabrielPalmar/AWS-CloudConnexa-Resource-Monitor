#!/bin/bash

# Check for dependencies
for pkg in mtr bc jq python3 python3-pip; do
    if ! command -v $pkg &> /dev/null; then
        sudo apt install $pkg -y &> /dev/null
    fi
done

if [[ -f "/opt/aws/amazon-cloudwatch-agent/bin/config.json" ]]; then
    echo -e "\n••••••••••• CloudWatch Agent already installed •••••••••••\n"
else
    # Set CloudWatch Agent
    sudo wget -q https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
    sudo dpkg -i -E ./amazon-cloudwatch-agent.deb &> /dev/null
    echo '{"agent":{"run_as_user":"root"},"logs":{"logs_collected":{"files":{"collect_list":[{"file_path":"/home/ubuntu/Connexa-Logs/**","log_group_class":"STANDARD","log_group_name":"CloudConnexa-Monitor-Logs","log_stream_name":"{instance_id}","retention_in_days":-1}]}}}}' > /opt/aws/amazon-cloudwatch-agent/bin/config.json
    sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json &> /dev/null
fi

script_dir='/home/ubuntu/connexa-script.sh'

if ! command openvpn3 --help &> /dev/null; then
    # Install the OpenVPN repository key used by the OpenVPN packages
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://packages.openvpn.net/packages-repo.gpg | sudo tee /etc/apt/keyrings/openvpn.asc &> /dev/null

    # Add the OpenVPN repository
    echo "deb [signed-by=/etc/apt/keyrings/openvpn.asc] https://packages.openvpn.net/openvpn3/debian $(lsb_release -c -s) main" | sudo tee /etc/apt/sources.list.d/openvpn-packages.list &> /dev/null
    sudo apt update &> /dev/null

    # Install OpenVPN Connector setup tool
    sudo apt install python3-openvpn-connector-setup -y &> /dev/null
fi

if sudo openvpn3 sessions-list | grep -A 2 'CloudConnexa' | grep -qo 'Client connected'; then
    echo -e "\n••••••••••• Using existing session •••••••••••\n"
else
    # Run openvpn-connector-setup to import ovpn profile and connect to VPN.
    echo -e "\n••••••••••• Place Host Connector Token •••••••••••"
    sudo openvpn-connector-setup 
fi

prompt_and_read() {
    local prompt_message=$1
    local variable_name=$2

    while true; do
        echo "$prompt_message"
        read input
        if [[ $input =~ ^[0-9]{1,3}$ ]]; then
            eval $variable_name=$input
            break
        else
            echo 'Please enter a valid number (3 digits max):'
        fi
    done
}

separator() {
echo -e "\n••••••••••••••••••••••••••••••••••••••••••••••••••"
}

separator
prompt_and_read 'Interval (minutes) where the monitoring script repeats [Recommended 5]:' interval
separator
prompt_and_read 'How many times the connection test would be repeated against the resource IP or Domain? [Recommended 25]:' TestCount
separator
prompt_and_read 'Threshold for the Latency value (ms) to monitor [Recommended 75]:' LatencyThreshold
separator
prompt_and_read 'Threshold for the Loss value (%) to monitor [Recommended 5]:' LossThreshold
separator
echo 'Resource IPs or Domains to monitor, comma separated [no space in between]:'

while true; do
    read ResourceIP
    if [[ $ResourceIP =~ ^[a-zA-Z0-9,.-]+$ ]]; then
        break
    else
        echo 'Please enter a valid domains or IPs, comma separated (no space in between)'
    fi
done

# Monitor Script
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
count="TestCountReplace"
latency_flag=0
loss_flag=0
latency_threshold="LatencyThresholdReplace"
loss_threshold="LossThresholdReplace"
rips="ResourceIPReplace"
ips=($(echo "$rips" | tr ',' '\n'))
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

for ip in "${ips[@]}"; do
    if echo "$ip" | grep -q 'http'; then
        domain="$ip"
        ip=$(echo "$ip" | awk -F '/' '{print $3}')
    else
        domain="$ip"
    fi
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
        if [[ "$latency_flag" -eq 1 ]]; then
            latency="$hop_latency"
        else
            latency_test=$(ping -q -c "$count" -n4 "$ip")
            if echo "$latency_test" | grep -q '100% packet loss'; then
                curl_test=$(curl --connect-timeout 5 -o /dev/null -s -w "%{time_total}" "$ip")
                if [[ $? -ne 0 ]]; then
                    latency=0
                    hop_loss=100
                    loss_flag=1
                else
                    curl_out=$(echo "scale=2; ($curl_test * 1000) / 1" | bc -l)
                    if echo "$curl_out > 500" | bc -l | grep -q 1; then
                        latency=0
                        hop_loss=100
                        loss_flag=1
                    else
                        latency="$curl_out"
                        hop_loss=0
                    fi
                fi
            else
                latency=$(echo "$latency_test" | grep 'rtt' | awk -F '/' '{print $5}')
                if [[ -n "$latency" && $(echo "$latency > $latency_threshold" | bc -l) -eq 1 ]]; then
                latency_flag=1
                fi
            fi
        fi
        if [[ $latency_flag -eq 1 ]] || [[ $loss_flag -eq 1 ]]; then
            break
        fi
    done
    resource_ips+=($ip)
    if [[ $latency_flag -eq 1 ]] || [[ $loss_flag -eq 1 ]]; then
        break
    fi
done

json_rips=$(printf '%s\n' "${resource_ips[@]}" | jq -R . | jq -cs .)

# Get current CloudConnexa Gateway
path=$(sudo openvpn3 sessions-list | grep -B 3 'CloudConnexa' | grep -o '\S*/net/openvpn/\S*')
gateway_ip=$(sudo openvpn3-admin journal --path $path | grep 'via' | tail -1 | awk -F '[()]' '{print $2}')

if ! [[ "$latency_flag" -eq 1 ]] && ! [[ "$loss_flag" -eq 1 ]]; then
    mtr_id=0
fi

json_data="{\"HOSTNAME\": \"$hostname\",\"RESOURCE(S)\": $json_rips,\"GATEWAY_IP\": \"$gateway_ip\",\"LATENCY_FLAG\": \"$latency_flag\",\"LATENCY_(ms)\": \"$latency\",\"LATENCY_THRESHOLD_(ms)\": \"$latency_threshold\",\"LOSS_FLAG\": \"$loss_flag\",\"HOP_LOSS_(%)\": \"$hop_loss\",\"LOSS_THRESHOLD_(%)\": \"$loss_threshold\",\"MTR-ID_(YYYYMMDDHHMMSS)\": \"$mtr_id\"}"

if [[ -f "$json_file" ]]; then
    echo "$json_data" >> "$json_file"
else
    echo "$json_data" > "$json_file"
fi

if [[ $latency_flag -eq 1 ]] || [[ $loss_flag -eq 1 ]]; then
    if [[ $(echo "$hop_loss < 100" | bc -l) -eq 1 ]]; then
        echo "$mtr_report_resource" | sed "s/HOST.*/RESOURCE MTR: $mtr_id (Hop, Avg, Loss%)/" | tail -n +2 > "$directory/MTR-RESOURCE-$mtr_id.txt"
    fi
    mtr_report_gateway=$(mtr -r -n -c $count -o AL $gateway_ip)
    echo "$mtr_report_gateway" | sed "s/HOST.*/GATEWAY MTR: $mtr_id (Hop, Avg, Loss%)/" | tail -n +2 > "$directory/MTR-GATEWAY-$mtr_id.txt"
fi

rm -f "$lockfile"
EOF

sed -i "s/TestCountReplace/$TestCount/; s/LatencyThresholdReplace/$LatencyThreshold/; s/LossThresholdReplace/$LossThreshold/; s@ResourceIPReplace@$ResourceIP@" $script_dir

chmod +x /home/ubuntu/connexa-script.sh
(crontab -l 2>/dev/null; echo "*/$interval * * * * $script_dir") | crontab -