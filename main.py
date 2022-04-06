from tokenize import String
import itertools
from random import seed
from random import randint
from datetime import datetime
import argparse
import socket
import threading
import time
import os

interface='eth0'
last_packet_time=datetime.now()
# Initial Setup
seed(datetime.now())

# Returns:
# req_port, rec_port, req_address, rec_address
def process_args():
    # Read from kubernetes-specific env
    req_port = os.environ.get('REQUESTER_SERVICE_PORT')
    rec_port = os.environ.get('RECEIVER_SERVICE_PORT')
    req_address = os.environ.get('REQUESTER_SERVICE_HOST')
    rec_address = os.environ.get('RECEIVER_SERVICE_HOST')
    
    # Check for arg overrides 
    parser = argparse.ArgumentParser(description='Performing testing and reproduction of issues seen in OVNKubernetes connection tracking.')
    parser.add_argument('--req-port', metavar='Req_P', type=int,
                        help='the source port for request packets. Defaults to env `REQUESTER_SERVICE_PORT`', default=(int(req_port) if req_port != None else 0 ) )

    parser.add_argument('--rec-port', metavar='Rec_P', type=int,
                        help='the source port for receiver Pods packets. Defaults to env `RECEIVER_SERVICE_PORT`', default=(int(rec_port) if req_port != None else 0 ) )

    parser.add_argument('--req-address', metavar='Req_Addr', type=str,
                            help='the source IP addres for request packets. Defaults to env `REQUESTER_SERVICE_HOST`', default=str(req_address) )


    parser.add_argument('--rec-address', metavar='Rec_Addr', type=str,
                            help='the source IP addres for receiver packets. Defaults to env `RECEIVER_SERVICE_HOST`', default=str(rec_address) )

    parser.add_argument('--conn-end', metavar='Conn_End', type=str,
                            help='Whether the application should initiate the communication or wait to be initiated with. Options are "receiver" or "requester"', default="requester" )
    
    parser.add_argument('--protocol', metavar='Protocol', type=str,
                            help='The L4 protocol to be used with tests. Options are "udp" or "tcp"', default="udp" )
    
    parser.add_argument('--reinit', action=argparse.BooleanOptionalAction,
                            help='Re-initialise communication after context-timeout. This is only used if conn-end is "requester"', default=True )
    
    # Packet Processing Type
    args = parser.parse_args()

    return args.req_port, args.rec_port, args.req_address, args.rec_address, args.conn_end, args.protocol, args.reinit


def packet_msg():
    val = next(counter)
    rand = randint(0, 100)
    return f"{conn_end} counter {val} rand {rand}"

def packet_timer(e):
    while not e.is_set():
        time.sleep(1)
        seconds_delta = (datetime.now() - last_packet_time).seconds
        
        if seconds_delta > 0: 
            print(f"Time since last packet: {seconds_delta}")

        if seconds_delta > 1 and seconds_delta % 5 == 0:
            print("Context Deadline Exceeded")
            break
    os._exit(1)


req_port,  rec_port, req_address, rec_address, conn_end, protocol, reinit = process_args()
print(f"Req Port: {req_port}")
print(f"Rec Port: {rec_port}")
print(f"Req Address: {req_address}")
print(f"Rec Address: {rec_address}")
print(f"Connection End: {conn_end}")

# Run specific vars
listen_port = 0
counter = itertools.count()

# If initial requester, start the communication
if conn_end == "requester":
    dst = rec_address
    src = req_address
    dport=rec_port
    sport=req_port
else:
    dst = req_address
    src = rec_address
    dport=req_port
    sport=rec_port


# Fork to new thread Packet timer
e = threading.Event()
timer_thread = threading.Thread(target=packet_timer, args=(e,))
timer_thread.start()

# Configure AddressPorts for communication
hostname = socket.gethostname()
pod_ip = socket.gethostbyname(hostname)

srcAddressPort   = (pod_ip, sport)
dstAddressPort   = (dst, dport)

# # Expect to receive a packet to the same outgoing source
# NOTE: This stops after e.is_set() and there is a packet arriving. Dont' wanna use supersockets to work around this limitation
# UDP Socket config 
print(f"Source Address: {srcAddressPort}")
print(f"Destination Address: {dstAddressPort}")

UDPServerSocket = socket.socket(family=socket.AF_INET, type=socket.SOCK_DGRAM)
UDPServerSocket.bind(srcAddressPort)
bufferSize  = 1024

if conn_end == "requester":
    msgBytes = str.encode(packet_msg())
    UDPServerSocket.sendto(msgBytes, dstAddressPort)

while True:
    bytesAddressPair = UDPServerSocket.recvfrom(bufferSize)
    
    last_packet_time=datetime.now()
    print("recv from", bytesAddressPair)

    msgBytes = str.encode(packet_msg())
    UDPServerSocket.sendto(msgBytes, dstAddressPort)
    print("send to", (msgBytes, dstAddressPort))


timer_thread.join()

print("Closing gracefully")