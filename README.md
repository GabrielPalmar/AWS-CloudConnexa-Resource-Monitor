# AWS CloudConnexa Resource Monitor

## Table of contents
* [General info](#introduction)
* [Technologies](#technologies)
* [Script Logic](#script-logic)
* [Setup](#setup)
* [Usage](#usage)
* [CloudFormation Templates](#cloudformation-templates)
* [Logs](#logs)

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
The script is designed to analyze MTR (My Traceroute) reports for the resources you are monitoring. It examines the initial hops over the connection to the specified IP or domain. Since the CloudConnexa tunnel is utilized to access the resources, the first and/or second hop in the data center will be CloudConnexa gateways before reaching the final destination. Therefore, the script focuses on analyzing the first three hops of the MTR report to assess latency and packet loss.

Based on the packet loss or occurrences logs are created under the folder path ***/home/ubuntu/Connexa-Logs*** creating three types of files:

1. **LATENCY-LOSS-CONNEXA-REPORT.json**: JSON file showing all reports made, indicating the following values:
```
{
  "HOSTNAME": "$hostname",
  "RESOURCE(S)": $json_rips,
  "GATEWAY_IP": "$gateway_ip",
  "LATENCY_FLAG": "$latency_flag",
  "LATENCY_(ms)": "$latency",
  "LATENCY_THRESHOLD_(ms)": "$latency_threshold",
  "LOSS_FLAG": "$loss_flag",
  "HOP_LOSS_(%)": "$hop_loss",
  "LOSS_THRESHOLD_(%)": "$loss_threshold",
  "MTR-ID_(YYYYMMDDHHMMSS)": "$mtr_id"
}
```

## Setup
The stand-alone script is supported for Ubuntu 22.04. While it might work on other Ubuntu versions, most dependencies installations are optimized for this specific version.

To launch the script, paste the following command on the terminal:

```
sudo wget -qO - raw.githubusercontent.com/GabrielPalmar/AWS-CloudConnexa-Resource-Monitor/main/Stand-alone%20Script/CC-Monitor-Script.sh | bash
```

## Usage

## CloudFormation Templates

## Logs
