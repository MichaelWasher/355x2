#!/bin/bash

# NOTE: There are sleeps in this to make sure that each application can finish starting before continuing. These may not be long enough and cause an issue, but just re-run this once the flow-rules have expired.

set -x

term() {
    echo "Cancelling test..."
    pkill -P $$
    
    source ./scripts/kill.sh

    # Copy results back
    oc cp receiver:/receiver_logs receiver_logs
    oc cp requester:/requester_logs requester_logs

    exit 1
}
trap term SIGTERM SIGINT

# Add Resources
source ./scripts/setup.sh


# Copy files into Pods
oc cp main.py receiver:/receiver.py
oc cp main.py requester:/requester.py

# Get Pod IPs
export REQUESTER_POD_IP=`oc get pods requester -o jsonpath='{.status.podIP}'`

# Run the Test
oc exec -t receiver -- sh -c "python3 -u /receiver.py --req-address='${REQUESTER_POD_IP}' --conn-end='receiver' 2>&1 >receiver_logs" &
sleep 2
oc exec -t requester -- sh -c "python3 -u /requester.py --no-reinit 2>&1 >requester_logs" 

# Copy results back
#mkdir -p log_results
#oc cp receiver:/receiver_logs log_results/receiver_logs
#oc cp requester:/requester_logs log_results/requester_logs
