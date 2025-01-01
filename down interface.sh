#!/bin/sh

# Target IP address
TARGET_IP="google.com"

# Interface to block/allow ICMP
INTERFACE="lan"

# Maximum allowed latency in ms
MAX_LATENCY=500

# Number of checks required to confirm high/low latency
CHECK_COUNT=5
CHECK_FAIL_COUNT=5

# Temporary files to track latency counts
HIGH_LATENCY_COUNT_FILE="/tmp/high_latency_count"
LOW_LATENCY_COUNT_FILE="/tmp/low_latency_count"
FAIL_COUNT_FILE="/tmp/fail_count"

# Initialize counters
: > "$HIGH_LATENCY_COUNT_FILE"
: > "$LOW_LATENCY_COUNT_FILE"
: > "$FAIL_COUNT_FILE"


interface_down() {
  status=$(ifstatus "$INTERFACE" | grep -o '"up": true')

  # Check if the interface is up
  if [ "$status" = '"up": true' ]; then
    echo "The interface $INTERFACE is UP. Bringing it down..."
    ifdown $INTERFACE
    echo "$INTERFACE interface has been brought down."
  else
    echo "The interface $INTERFACE is already DOWN or inactive."
  fi
}

interface_up() {
  status=$(ifstatus "$INTERFACE" | grep -o '"up": false')

  # Check if the interface is up
  if [ "$status" = '"up": false' ]; then
    echo "The interface $INTERFACE is DOWN. Bringing it UP..."
    ifup $INTERFACE
    echo "$INTERFACE interface has been brought UP."
  else
    echo "The interface $INTERFACE is already UP."
  fi
}


while true; do
    # Measure latency using hping3
    LATENCY=$(hping3 -S -p 80 -c 1 "$TARGET_IP" 2>/dev/null | grep 'rtt=' | awk -F'rtt=' '{print $2}' | awk '{print $1}' | cut -d'/' -f1)

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
            echo "High latency sustained for $CHECK_COUNT checks, DOWN $INTERFACE interface..."
            interface_down
            : > "$HIGH_LATENCY_COUNT_FILE"
        elif [ $LOW_LATENCY_COUNT -gt $CHECK_COUNT ]; then
            echo "Low latency sustained for $CHECK_COUNT checks, UP $INTERFACE interface..."
            interface_up
            : > "$LOW_LATENCY_COUNT_FILE"
        fi

        : > "$FAIL_COUNT_FILE" # Reset fail count
    else
        echo "Failed to measure latency to $TARGET_IP"
        echo 1 >> "$FAIL_COUNT_FILE"
        FAIL_COUNT=$(wc -l < "$FAIL_COUNT_FILE")
        if [ $FAIL_COUNT -gt $CHECK_FAIL_COUNT ]; then
            echo "Failed to connect $FAIL_COUNT times in a row. DOWN $INTERFACE interface..."
            interface_down
            : > "$HIGH_LATENCY_COUNT_FILE"  # Reset high latency count
            : > "$LOW_LATENCY_COUNT_FILE"  # Reset low latency count
        fi
    fi

    sleep 1

done
