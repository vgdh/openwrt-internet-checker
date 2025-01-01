#!/bin/sh

# Target IP address
TARGET_IP="google.com"

# Interface to block/allow ICMP
INTERFACE="eth1"

# Maximum allowed latency in ms
MAX_LATENCY=500

# Number of checks required to confirm high/low latency
CHECK_COUNT=5
CHECK_FAIL_COUNT=5

# Temporary files to track latency counts
HIGH_LATENCY_COUNT_FILE="/tmp/high_latency_count"
LOW_LATENCY_COUNT_FILE="/tmp/low_latency_count"
FAIL_COUNT_FILE="/tmp/fail_count"

FIREWALL_RULE_NAME="icmp_auto_block"
FIREWALL_SRC_ZONE="lan"

# Initialize counters
: > "$HIGH_LATENCY_COUNT_FILE"
: > "$LOW_LATENCY_COUNT_FILE"
: > "$FAIL_COUNT_FILE"

create_rule() {
rule_exist=$(uci show firewall | grep -B 1 "$FIREWALL_RULE_NAME" | head -n 1 | cut -d'.' -f2 | cut -d'=' -f1)
#
if [ -n "$rule_exist" ]; then
  echo "The rule already exist"
else
  echo "The rule doesn't exist. Let's create one"
  #
  uci add firewall rule
  uci set firewall.@rule[-1].name="$FIREWALL_RULE_NAME"
  uci set firewall.@rule[-1].proto='icmp'
  uci set firewall.@rule[-1].target='ACCEPT'
  uci set firewall.@rule[-1].src="$FIREWALL_SRC_ZONE"
  uci commit firewall
  /etc/init.d/firewall reload
fi
}

block_icmp() {
rule_id=$(uci show firewall | grep -B 1 "$FIREWALL_RULE_NAME" | head -n 1 | cut -d'.' -f2 | cut -d'=' -f1)
rule_target=$(uci get firewall."$rule_id".target)
#
if [ $rule_target = "DROP" ]; then
  echo "ICMP target is already set to DROP"
else
  echo "Set ICMP target to DROP"
  #
  uci set firewall."$rule_id".target='DROP'
  uci commit firewall
  /etc/init.d/firewall reload
fi
}

allow_icmp() {
rule_id=$(uci show firewall | grep -B 1 "$FIREWALL_RULE_NAME" | head -n 1 | cut -d'.' -f2 | cut -d'=' -f1)
rule_target=$(uci get firewall."$rule_id".target)
#
if [ $rule_target = "ACCEPT" ]; then
  echo "ICMP target is already set to ACCEPT"
else
  echo "Set ICMP target to ACCEPT"
  #
  uci set firewall."$rule_id".target='ACCEPT'
  uci commit firewall
  /etc/init.d/firewall reload
fi
}


while true; do
    # Measure latency using hping3
    LATENCY=$(hping3 -S -p 80 -c 1 "$TARGET_IP" 2>/dev/null | grep 'rtt=' | awk -F'rtt=' '{print $2}' | awk '{print $1}' | cut -d'/' -f1)
    
    create_rule # Create rule if it doesn't exist

    if [[ -n "$LATENCY" ]]; then
        LATENCY=${LATENCY%.*} # Convert to integer for comparison

        if [ $LATENCY -gt $MAX_LATENCY ]; then
            echo "$LATENCY ms exceeds $MAX_LATENCY ms"
            echo 1 >> "$HIGH_LATENCY_COUNT_FILE"
            : > "$LOW_LATENCY_COUNT_FILE"  # Reset low latency count
        else
            echo "$LATENCY ms within acceptable range"
            echo 1 >> "$LOW_LATENCY_COUNT_FILE"
            : > "$HIGH_LATENCY_COUNT_FILE"  # Reset high latency count
        fi

        HIGH_LATENCY_COUNT=$(wc -l < "$HIGH_LATENCY_COUNT_FILE")
        LOW_LATENCY_COUNT=$(wc -l < "$LOW_LATENCY_COUNT_FILE")

        if [ $HIGH_LATENCY_COUNT -gt $CHECK_COUNT ]; then
            echo "High latency sustained for $CHECK_COUNT checks, blocking ICMP..."
            block_icmp
            : > "$HIGH_LATENCY_COUNT_FILE"
        elif [ $LOW_LATENCY_COUNT -gt $CHECK_COUNT ]; then
            echo "Low latency sustained for $CHECK_COUNT checks, allowing ICMP..."
            allow_icmp
            : > "$LOW_LATENCY_COUNT_FILE"
        fi

        : > "$FAIL_COUNT_FILE" # Reset fail count
    else
        echo "Failed to measure latency to $TARGET_IP"
        echo 1 >> "$FAIL_COUNT_FILE"
        FAIL_COUNT=$(wc -l < "$FAIL_COUNT_FILE")
        if [ $FAIL_COUNT -gt $CHECK_FAIL_COUNT ]; then
            echo "Failed to connect $FAIL_COUNT times in a row. Blocking ICMP."
            block_icmp
            : > "$HIGH_LATENCY_COUNT_FILE"  # Reset high latency count
            : > "$LOW_LATENCY_COUNT_FILE"  # Reset low latency count
        fi
    fi

    sleep 1

done
