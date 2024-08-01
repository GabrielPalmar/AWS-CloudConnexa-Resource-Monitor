# AWS CloudConnexa Resource Monitor

## Table of contents
* [General info](#introduction)
* [Technologies](#technologies)
* [Script Logic](#script-logic)
* [Setup](#setup)
* [Usage](#usage)
* [CloudFormation Templates](#cloudformation-templates)

## Introduction
Monitor script that continually checks the latency and packet loss of resources in CloudConnexa and logs reports if any anomalies occur along the path.

AWS CloudWatch Logs and Alarms can be set up to respond to any disruptions in the connection.
	
## Technologies
Code:
- Bash
  
AWS:
- CloudFormation
- CloudWatch
- EC2
- IAM Roles

CloudConnexa:
- OpenVPN3
- Host Connection

## Script Logic
The script analyzes MTR (My Traceroute) reports for your monitored resources. It examines the initial hops over the connection to the specified IP(s) or domain(s). Since the CloudConnexa tunnel is utilized to access the resources, the first and/or second hop in the data center will be CloudConnexa gateways before reaching the final destination. Therefore, the script examines the first three hops of the MTR report to assess latency and packet loss.

Based on the packet loss or occurrences, logs are created under the folder path ***/home/ubuntu/Connexa-Logs***, creating three types of files:

1. **LATENCY-LOSS-CONNEXA-REPORT.json**: Single JSON file constantly updated, showing all reports made with the script, indicating the following values:
```
{
  "HOSTNAME": "Hostname of the machine",
  "RESOURCE(S)": "IPs or Domains (comma-separated)",
  "GATEWAY_IP": "CloudConnexa Gateway IP used for the Tunnel",
  "LATENCY_FLAG": "Flag if latency is found",
  "LATENCY_(ms)": "Latency value of the LAST checked resource",
  "LATENCY_THRESHOLD_(ms)": "Threshold set for latency",
  "LOSS_FLAG": "Flag if packet loss is found",
  "HOP_LOSS_(%)": "Packet loss value of the LAST checked resource",
  "LOSS_THRESHOLD_(%)": "Threshold set for packet loss",
  "MTR-ID_(YYYYMMDDHHMMSS)": "Unique identifier to find MTR reports"
}
```
Please keep in mind that when checking multiple resources with the script, if there is no packet loss or latency, the "**LATENCY_(ms)**" and "**HOP_LOSS_(%)**" values will refer to the last domain or IP address entered in the script for checking.

2. **MTR-RESOURCE-{mtr_id}.txt**: A created MTR report containing packet loss or latency values over the hops against. This report is skipped in case of a 100% packet loss over the connection.

3. **MTR-GATEWAY-$mtr_id.txt**: A created MTR report containing packet loss or latency values over the hops against the CloudConnexa Gateway IP used by the OpenVPN3 Client. This report is important for the CloudConnexa support team as it allows us to check if there is an issue over the CloudConnexa region DC.

Note: Each MTR report has a unique MTR ID to filter and easily access.

![](https://github.com/GabrielPalmar/AWS-CloudConnexa-Resource-Monitor/blob/main/Diagram.png?raw=true)

## Setup
The stand-alone script is supported for Ubuntu 22.04. While it might work on other Ubuntu versions, most dependencies installations are optimized for this specific version.

To launch the script, paste the following command on the terminal:

```
sudo wget -qO - raw.githubusercontent.com/GabrielPalmar/AWS-CloudConnexa-Resource-Monitor/main/Stand-alone%20Script/CC-Monitor-Script.sh | bash
```

## Usage

## CloudFormation Templates
