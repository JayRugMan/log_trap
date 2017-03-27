#!/bin/bash
# alert_trap_IPMI_CPU.sh
# This script monitors a cluster management server's logs for IPMI related alerts
# sent from the members of the cluster(s) it manages. 
#
#############################################################################################
#                                                                                           #
# Sequence of actions:                                                                      #
#  1- defines arguments and functions                                                       #
#  2- check user inputs                                                                     #
#  3- starts loop to monitor for IPMI alerts                                                #
#  4- if the last line of the log is already in the trap then the script loops until        #
#     a new log entry appears in the log file                                               #
#  5- the script will loop again until an alert is raised for IPMI info thus springing      #
#     the trap                                                                              #
#  6- the last line is then loaded into an argument, as well as it's time, parsed to        #
#     give that log line a unique identification, and prints that log line                  #
#  7- determines the server and cluster with an issue from the log output                   #
#     !! these awk statements may need to be modified based on the specific log outputs !!  #
#  8- from the specified IP list, determines the server's IP address and, through ssh,      #
#     sends IPMI and mpstat commands directed to a file in that server's /var/tmp/          #
#  9- if the IP address in not on the list of used IP addresses (ip_address_list), it is    #
#     then added                                                                            #
# 10- once the loop completes the specified iterations, the output files are gathered       #
#     and deleted from the remote servers using ip_address_list                             #
# 11- the files are then displayed (hardcoded location is /var/tmp/)                        #
#                                                                                           #
#############################################################################################


echo "======= script start time: $(date +%T) ======="

## specifies the log and gathers the SC info to save time later
loop_iteration=1
ip_loop_iteration=0
logline_loop_iteration=0
logtime=0
blah_bit=0

fGetArgs() {
    echo -e "\n\talert_trap_IPMI_CPU.sh\n four arguments are required:"
    read -p " 1- absolute path to the cluster manager's log file: " -e alert_log
    read -p " 2- IP list of servers in the cluster:               " -e IP_list
    read -p " 3- absolute path of the ssh identity key:           " -e identity_key
    read -p " 4- number of iterations (default is 3):             " -e loop_limit
    echo
    if [ -z ${loop_limit} ]; then
        loop_limit=3
    fi
}

## checks if argument one is an element in argument two (an array)
f_contains_element() {
    local k
    for k in "${@:2}"; do 
        [[ "${k}" == "$1" ]] && return 0
    done
    return 1
}

fGetArgs

## verifies that a log file is specified,
## list of cluster node IP addresses,
## ssh identity key,
## and a numeric value
if [ -z ${alert_log} ]; then
    echo -e "\n you need to specify an alert log"
    exit 1
elif [ -z ${IP_list} ]; then
    echo -e "\n you need to create and specify an a list of IP addresses
    \b\b\bexample IP list file contents:
    \b\b\bcluster-1 node_1 10.10.10.1
    \b\b\bcluster-1 node_2 10.10.10.2
    \b\b\bcluster-1 node_3 10.10.10.3
    \b\b\bcluster-1 node_4 10.10.10.4
    \b\b\bcluster-2 node_1 10.10.11.1
    \b\b\bcluster-2 node_2 10.10.11.2\n\n"
    exit 1
elif [ -z ${identity_key} ]; then
    echo -e "\n you need to specify an ssh itentity key"
    exit 1
elif ! [[ ${loop_limit} =~ ${is_digit} ]]; then
    echo -e "\n - please enter an integer for the number of iterations.\n"
    exit 1
fi

## loops for the number of iterations specified in loop_limit
while [[ ${loop_iteration} -le ${loop_limit} ]]; do
    
    echo -e "\n===== loop iteration ${loop_iteration} start time: $(date +%T) ====="
    
    ## will loop until the last log entry is no longer the alert caught in the previous iteration
    if [[ ${loop_iteration} -ne 1 ]]; then
        echo -n " waiting for next log entry..."
        blah_bit=1
    fi
    while [[ $(tail -1 ${alert_log} | awk -F'[- :,]' '{print $1$2$3$4$5$6$7}') == ${logtime} ]]; do
        echo -ne "\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b waiting for next log entry..."
    done
    
    ## will loop and repeat "working" as long as the last line of the alert log does not contain "Raised alert" and IPMI together
    if [[ ${blah_bit} -eq 1 ]]; then
        echo -ne "\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b working...                   "
    else
        echo -n " working...                   "
    fi
    
    ## gets the SC-name and cluster name from the alert log line
    ## !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    ## ! These lines will need to be edited based on the expected alert log output: !
    ## !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    while `tail -1 ${alert_log} | awk '/Raised alert/ && /IPMI/ {count++}; END{if (count>=1) print "false"; else print "true"}'`; do
    ## !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        echo -ne "\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b working...                   "
    done
    
    ## puts the last line of alert log into an argument
    log_line=$(tail -1 ${alert_log})
    logtime=$(echo "${log_line}" | awk -F'[- :,]' '{print $1$2$3$4$5$6$7}')
    
    echo -e "\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b - gathering info - loop done time: $(date +%T)"
    echo -e " - logline in trap:\n\n${log_line}\n"
    
    ## gets the SC-name and cluster name from the alert log line
    ## !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    ## ! These lines will need to be edited based on the expected alert log output: !
    ## !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    server_with_issue=$(echo "${log_line}" | awk -F'(object: | \\[)' '{print $2}')
    cluster_with_issue=$(echo "${log_line}" | awk -F'(: )' '{print $2}')
    ## !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    
    ## gets the IP address from IP_list using server_with_issue and cluster_with_issue 
    server_ip_address=$(awk -v cluster="${cluster_with_issue}" -v server="${server_with_issue}"  '$0 ~ cluster && $0 ~ server {print $3}' ${IP_list})
    
    echo " - ssh sending time: $(date +%T)"
    
    ## sends an IPMI command for sense data to the SC that sent the alert and saves it to a file with time stamps
    ssh -x -i ${identity_key} root@${sc_ip_address} "echo \" - before mpstat command time: \$(date +%D) \$(date +%T) \" >> /var/tmp/cpu_data__\$(hostname).out; \
            mpstat -P ALL >> /var/tmp/cpu_data__\$(hostname).out; \
            echo \" - after mpstat command time: \$(date +%D) \$(date +%T) \" >> /var/tmp/cpu_data__\$(hostname).out; \
            echo \" - before IPMI command time: \$(date +%D) \$(date +%T) \" >> /var/tmp/ipmi_sense__\$(hostname).out; \
            ipmitool sensor >> /var/tmp/ipmi_sense__\$(hostname).out; \
            echo \" - after IPMI command time: \$(date +%D) \$(date +%T) \" >> /var/tmp/ipmi_sense__\$(hostname).out"
    
    echo " - ssh sent time: $(date +%T)"
    
    ## if the IP address has already been added to the list, it won't be added again
    if ! f_contains_element ${sc_ip_address} ${ip_address_list[@]}; then
        ip_address_list[${ip_loop_iteration}]=${sc_ip_address}
        ((ip_loop_iteration++))
    fi
    
    echo -e " - loop iteration ${loop_iteration} end time: $(date +%T)\n"
    ((loop_iteration++))
done

## gathers and deletes the file once it's obtained
for i in ${ip_address_list[@]}; do 
    echo
    ping -c 1 "${i}" >> ./ping.out #2>&1
    egrep "1 received" ./ping.out
    if [ $? -eq 0 ]; then
        echo " - ssh sending time: $(date +%T) - ping for ${i} successful - gathering ..."
        scp -i ${identity_key} root@${i}:/var/tmp/ipmi_sense__*.out /var/tmp/ &&\
        ssh -x -i ${identity_key} root@${i} "rm -f /var/tmp/ipmi_sense__*.out"
        scp -i ${identity_key} root@${i}:/var/tmp/cpu_data__*.out /var/tmp/ &&\
        ssh -x -i ${identity_key} root@${i} "rm -f /var/tmp/cpu_data__*.out"
    else
        echo " - fail time: $(date +%T) - ping for ${i} failed"
    fi
    echo "" > ./ping.out
done

echo -e "\n\n output files in /var/tmp:\n\n$(ls -t1 /var/tmp/ | grep -E "ipmi_sense_|cpu_data_")\n\n"
### lines to add to the end of a file to simulate the trap triggers. Used for testing the script
## echo '2017-02-27 13:27:40,714: cluster-1: Raised alert: "Server temperature IPMI information is unavailable." object: node_1 [16] severity: minor' >> /var/log/xms/dummy.alert.log
## echo '2017-02-27 13:27:41,714: cluster-1: Removed alert: "Server temperature IPMI information is unavailable." object: node_1 [16] severity: minor' >> /var/log/xms/dummy.alert.log
## echo '2017-02-27 13:27:46,714: cluster-1: Raised alert: "Server temperature IPMI information is unavailable." object: node_1 [16] severity: minor' >> /var/log/xms/dummy.alert.log
## echo '2017-02-27 13:27:47,714: cluster-1: Removed alert: "Server temperature IPMI information is unavailable." object: node_1 [16] severity: minor' >> /var/log/xms/dummy.alert.log
## echo '2017-02-27 13:27:50,714: cluster-1: Raised alert: "Server temperature IPMI information is unavailable." object: node_2 [16] severity: minor' >> /var/log/xms/dummy.alert.log
## echo '2017-02-27 13:27:51,714: cluster-1: Removed alert: "Server temperature IPMI information is unavailable." object: node_2 [16] severity: minor' >> /var/log/xms/dummy.alert.log
## echo '2017-02-27 13:27:55,714: cluster-1: Raised alert: "Server temperature IPMI information is unavailable." object: node_4 [16] severity: minor' >> /var/log/xms/dummy.alert.log
## echo '2017-02-27 13:27:56,714: cluster-1: Removed alert: "Server temperature IPMI information is unavailable." object: node_4 [16] severity: minor' >> /var/log/xms/dummy.alert.log
## echo '2017-02-27 13:27:57,714: cluster-1: Raised alert: "Server temperature IPMI information is unavailable." object: node_2 [16] severity: minor' >> /var/log/xms/dummy.alert.log
## echo '2017-02-27 13:27:58,714: cluster-1: Removed alert: "Server temperature IPMI information is unavailable." object: node_2 [16] severity: minor' >> /var/log/xms/dummy.alert.log
