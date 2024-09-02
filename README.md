# AWS CloudConnexa Resource Monitor

## Table of contents
* [Introduction](#introduction)
* [Technologies](#technologies)
* [Script Logic](#script-logic)
* [Prerequisites](#prerequisites)
* [Setup](#setup)
* [Usage](#usage)
* [CloudFormation Templates](#cloudformation-templates)
* [Caveats](#caveats)

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
- Unified CloudWatch Agent

CloudConnexa:
- OpenVPN3
- Host Connection

## Script Logic
The script analyzes MTR (My Traceroute) reports for your monitored resources. It examines the initial hops over the connection to the specified IP(s) or domain(s). Since the CloudConnexa tunnel is utilized to access the resources, the first and/or second hop will be the CloudConnexa gateways before reaching the final destination. Therefore, the script examines the first three hops of the MTR report to assess latency and packet loss.

The resources are also monitored with PING tests; this value takes precedence over the MTR hops latency and is evaluated against the script's threshold value.

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

## Prerequisites
To send the logs to CloudWatch Logs, an IAM role with specific permissions must be attached to the EC2 instance.
1. Permissions:

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "LogsPermissions",
            "Effect": "Allow",
            "Action": [
                "logs:DescribeLogStreams",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogGroups"
            ],
            "Resource": [
                "arn:aws:logs:*:{Account-ID}:log-group:CloudConnexa-Monitor-Logs:*"
            ]
        }
    ]
}
```
Replace "**{Account-ID}**" with your AWS Account ID.

2. Trust Relationships:
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
```
Attach the role to the EC2 instance during creation or to an existing EC2 instance using the steps shown here: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html#working-with-iam-roles

The EC2 will push the logs to the CloudWatch Group called "**CloudConnexa-Monitor-Logs**" using the Unified CloudWatch Agent. If this Log Group is not created, it will be created automatically once the logs are pushed. You can also create the Log Group in advance using the [CloudFormation Template](#cloudformation-templates), including creating the Filter to find latency or loss flags.

To create the CloudWatch Filter manually, use the following [filter pattern with regex](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/FilterAndPatternSyntax.html):

```
{ ($.LATENCY_FLAG = "1") || ($.LOSS_FLAG = "1") }
```

## Setup
The stand-alone script is supported for Ubuntu 22.04. While it might work on other Ubuntu versions, most dependencies installations are optimized for this specific version.

To launch the script, use the following on the EC2's terminal:

```
wget -q raw.githubusercontent.com/GabrielPalmar/AWS-CloudConnexa-Resource-Monitor/main/Stand-alone%20Script/CC-Monitor-Script.sh
chmod +x CC-Monitor-Script.sh
sudo ./CC-Monitor-Script.sh
```

You can also consider using the [CloudFormation Template](#cloudformation-templates) to launch all the settings, including a new EC2.

## Usage

- An interactive mode is used when launching the script, requesting the following information:
1. **Interval (minutes) where the monitoring script repeats**: Dictates the interval in minutes for the cronjob to be repeated.
2. **How many times would the connection test be repeated against the resource IP or Domain?**: Test count for the MTR should be repeated. A higher value yields better average results but increases completion time.
3. **Threshold for the Latency value (ms) to monitor**: Threshold value for the latency tests to be compared. For example, if you choose 75, any report yielding higher latency than 75ms will trigger the flag.
4. **Threshold for the Loss value (%) to monitor**: Threshold value for the latency tests to be compared. For example, if you choose 5, any report yielding higher packet loss than 5% will trigger the flag.
5. **Resource IPs or Domains to monitor, comma separated [no space in between]**: Domains or IPs of the CloudConnexa resources you want to monitor, for example, "_privatedomain.com,192.168.1.15,10.10.1.10_'.

NOTE: If this script is placed in a fresh EC2, it will ask for a [Host Token](https://openvpn.net/cloud-docs/owner/tutorials/configuration-tutorials/connectors/operating-systems.html#tutorial--install-a-connector-on-linux) to install the CloudConnexa session.

- Once the script is installed, you can manually edit the values over the script file:
```
/home/ubuntu/connexa-script.sh
```

- Also, you can edit the cronjob interval or remove the job by using the following command:
```
crontab -e
```

- Remember to set up the CloudWatch alarm and configure the required SNS topic to receive alerts when a flag is triggered: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Alarm-On-Logs.html.

## CloudFormation Templates
1. Template to launch the Monitor script, including EC2, IAM roles, and CloudWatch [configuration](#dios):
   
[![Launch Stack](https://cdn.rawgit.com/buildkite/cloudformation-launch-stack-button-svg/master/launch-stack.svg)](https://console.aws.amazon.com/cloudformation/home#/stacks/new?stackName=CC-Resource-Monitor&templateURL=https://aws-cloudconnexa-resource-monitor.s3.us-east-2.amazonaws.com/CF-CC-Monitor-Template.yaml)

2. Template to create the CloudWatch Log Group and Filter:
   
[![Launch Stack](https://cdn.rawgit.com/buildkite/cloudformation-launch-stack-button-svg/master/launch-stack.svg)](https://console.aws.amazon.com/cloudformation/home#/stacks/new?stackName=CC-CloudWatch&templateURL=https://aws-cloudconnexa-resource-monitor.s3.us-east-2.amazonaws.com/CF-CC-CloudWatch-Template.yaml)

## Caveats
The monitoring script depends on the MTR application. While creating it, I discovered a bug in the report mode used to review the hops. I have submitted a bug request. You can follow this request by using this link: https://bugs.launchpad.net/ubuntu/+source/mtr/+bug/2070685. 

Based on this, a PING test checks the latency and packet loss to the destination as failover to ensure the script works properly.
