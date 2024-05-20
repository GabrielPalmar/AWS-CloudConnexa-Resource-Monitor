#!/bin/bash

mtr_report=$(mtr -r -n -c 25 -o AL 192.168.144.47)

for hop in {3..5}; do 
    echo "$mtr_report" | sed -n "$hop p"
done