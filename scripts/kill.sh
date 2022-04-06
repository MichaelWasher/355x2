#!/bin/bash
set -x

oc rsh receiver killall python3
oc rsh requester killall python3
