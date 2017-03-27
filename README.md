# log_trap
bash script that monitors cluster management server logs for specific alerts and reaches out to the specified node for raw data.

Sequence of actions:                                                                      
 1- defines arguments and functions                                                       
 2- check user inputs                                                                     
 3- starts loop to monitor for IPMI alerts                                                
 4- if the last line of the log is already in the trap then the script loops until        
    a new log entry appears in the log file                                               
 5- the script will loop again until an alert is raised for IPMI info thus springing      
    the trap                                                                              
 6- the last line is then loaded into an argument, as well as it's time, parsed to        
    give that log line a unique identification, and prints that log line                  
 7- determines the server and cluster with an issue from the log output                   
    !! these awk statements may need to be modified based on the specific log outputs !!  
 8- from the specified IP list, determines the server's IP address and, through ssh,      
    sends IPMI and mpstat commands directed to a file in that server's /var/tmp/          
 9- if the IP address in not on the list of used IP addresses (ip_address_list), it is    
    then added                                                                            
10- once the loop completes the specified iterations, the output files are gathered       
    and deleted from the remote servers using ip_address_list                             
11- the files are then displayed (hardcoded location is /var/tmp/)
