#!/bin/bash

# Ensure collector pod present
oc project 355x2
oc adm policy add-cluster-role-to-user cluster-admin -z default 
oc apply -f ./manifests/collector-pods.yaml

debug_pods=("receiver-collector" "requester-collector")

# Keepalive is to avoid stale/timout issues with `oc debug/exec` requests
keepalive() {
    while true; do
        sleep 1
        echo -n .
    done
}
# Triger PCAP in Pod
pcap_outer(){
    keepalive &
    mkdir -p /host/tmp/collect/
    pod_name=$1
    cont_id=`oc get pods -o json ${pod_name} | jq -r '.status.containerStatuses[0].containerID' | cut -d '/' -f 3`
    pid=`chroot /host crictl inspect --output json $cont_id | jq .info.pid`
    ifindex=$(nsenter -t $pid -n ip link | sed -n -e 's/.*eth0@if\([0-9]*\):.*/\1/p')
    veth=`ip -o link | grep ^$ifindex | cut -d ":" -f 2 | cut -d "@" -f 1`
    tcpdump -i $veth -w /host/tmp/collect/${pod_name}-outer.pcap
}

pcap_any(){
    keepalive &
    mkdir -p /host/tmp/collect/
    tcpdump -i any -w /host/tmp/collect/any.pcap
}

pcap_inner(){
    keepalive &
    mkdir -p /host/tmp/collect/
    pod_name=$1
    cont_id=`oc get pods -o json $1 | jq -r '.status.containerStatuses[0].containerID' | cut -d '/' -f 3`
    pid=`chroot /host crictl inspect --output json $cont_id | jq .info.pid`
    nsenter -n -t $pid -- tcpdump -i any -w /host/tmp/collect/${pod_name}.pcap
}

conntrack_events(){
    keepalive &
    mkdir -p /host/tmp/collect/
    chroot /host conntrack -E -o extended,timestamp 2>&1 > /host/tmp/collect/conntrack-events.txt
}

collect(){
    collect_pod=$1
    target_pod=$2

    oc exec -t "${collect_pod}" -- sh -c "$pod_script; conntrack_events" &
#   oc exec -t "${collect_pod}" -- sh -c "$pod_script; pcap_any" &

    oc exec -t "${collect_pod}" -- sh -c "$pod_script; pcap_outer ${target_pod}" &
    oc exec -t "${collect_pod}" -- sh -c "$pod_script; pcap_inner ${target_pod}" &
}

term() {
    echo "Completed TCPMDump"
    pkill -P $$
    
    for pod in "${debug_pods[@]}"; do
        oc exec -t "${pod}" -- sh -c "killall tcpdump conntrack" 
        
        echo "Collecting PCAPs from "
        #oc cp  ${pod}:/host/tmp/collect/ ./collect-${pod}
    done
}
trap term SIGTERM SIGINT


pod_script=$(declare -f keepalive pcap_any pcap_outer pcap_inner conntrack_events)

echo "----------------------------------------------------------"
echo "Starting the pcaps. These will run until failure of killed. Kill with Crtl + C to copy back the contents"
echo "----------------------------------------------------------"

for pod in "${debug_pods[@]}"; do
  echo "Collecting data from $pod"
  target_pod=`echo -n ${pod} | cut -d - -f 1`
  collect $pod $target_pod
done

wait
