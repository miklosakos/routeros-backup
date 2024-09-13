#!/bin/bash

### GENERIC EXAMPLE CONFIG
###
### sshusr=backup
### keyfile=/data/vault/sshkeys/backup/mikrotik/site-a/fwl01
### backuppath=/data/vault/backups
### 

### ROUTER SPECIFIC EXAMPLE CONFIG
###
### sshusr=backup_user
### keyfile=/data/vault/sshkeys/backup/mikrotik/site-b/fwl04
### backuppath=/data/vault/backups/site-b/fwl04
### hostname=fwl04.site-b.acme
### dateformat=%Y-%m-%d
### timeformat=%H:%M:%S
### logfile=mikrotik-b-fwl04.backup.log
### host=10.200.128.254


# script init


## handle arguments

sendhelp() {
        echo "/--------------------------------------------------------------------------------------------------------------------------------------\\"
        echo "|                                                            SCRIPT USAGE                                                             |"
        echo "|.....................................................................................................................................|"
        echo "|                                                            WITHOUT CONFIG                                                           |"
        echo "|                                                                                                                                     |"
        echo "| mikrotikbackup.sh -h <routerip> -k <private key file> -u <sshuser> -p <path to dump files> -b <backup file name> -l <log file name> |"
        echo "|=====================================================================================================================================|"
        echo "|                                                              WITH CONFIG                                                            |"
        echo "|                                             mikrotikbackup.sh -h <routerip> -c <config>                                             |"
        echo "\\-------------------------------------------------------------------------------------------------------------------------------------/"
}

while getopts "h:c:k:u:p:b:l:" option; do
        case $option in
                h)
                        host=${OPTARG}
                        ;;
                c)
                        if test -f ${OPTARG}; then
                                conf=${OPTARG}
                        else
                                echo "Config file does not exist"
                                exit 252
                        fi
                        ;;
                k)
                        if test -f ${OPTARG}; then
                                keyfile=${OPTARG}
                        else
                                echo "SSH private key file does not exist"
                                exit 254
                        fi
                        ;;
                u)
                        sshuser=${OPTARG}
                        ;;
                p)
                        if test -d ${OPTARG}
                        then
                                backuppath=${OPTARG}
                        else
                                echo "Destination directory does not exist"
                                exit 253
                        fi
                        ;;
                b)
                        backupfilename=${OPTARG}
                        ;;
                l)
                        logfile=${OPTARG}
                        ;;
                *)
                        sendhelp
                        exit 99        
        esac
done

if [ $OPTIND -eq 1 ]
then
        sendhelp
        exit 99
fi

# ========================================================================================================================================================================================

# check for req'd args and set defaults for optional args if needed

noconf=false

if [ -z $conf ]
then
        echo "No config provided"
        if [ -z $host ]
        then
                echo "[PRE-RUN CHECK FATAL ERROR] You MUST supply a router to backup"
                exit 255
        fi
        if [ -z $keyfile ]
        then
                echo "[PRE-RUN CHECK FATAL ERROR] You MUST supply a keyfile to use!"
                exit 254
        fi
        if [ -z $sshuser ]
        then
                echo "No SSH user supplied, setting sshuser to backup"
                sshuser="backup"
        fi
        if [ -z $backuppath ]
        then
                echo "Backup target path not specified, falling back to $(pwd)."
                backuppath=$(pwd)
        fi
        noconf=true
fi

# ========================================================================================================================================================================================

# setup our config and rotated arrays

typeset -A config
config=(
        [sshusr]="$sshuser"
        [keyfile]="$keyfile"
        [dateformat]="%Y-%m-%d"
        [backuppath]=$backuppath
        [logfile]="$logfile"
        [backupfilename]="$backupfilename"
        [hostname]=""
        [timeformat]="%H:%M:%S"
        [host]=$host
)

typeset -A rotated
rotated=(
        [runlog]=false
        [runlogname]=""
)

# ========================================================================================================================================================================================

# if config file exists, load values from it

if [ $noconf = false ];
then
        while read cfgl
        do
                if echo $cfgl | grep -F '=' &>/dev/null
                then
                        var=$(echo "$cfgl" | cut -d '=' -f 1)
                        config[$var]=$(echo "$cfgl" | cut -d '=' -f 2)
                fi
        done <$conf

# if the user supplied command line arguments even with a config file, use them as override

        if [ ! -z $sshuser ]
        then
                config[sshusr]=$sshuser
        fi
        if [ ! -z $backuppath ]
        then
                config[backuppath]=$backuppath
        fi
        if [ ! -z $backupfilename ]
        then
                config[backupfilename]=$backupfilename
        fi
        if [ ! -z $logfile ]
        then
                config[logfile]=$logfile
        fi
        if [ ! -z $keyfile ]
        then
                config[keyfile]=$keyfile
        fi
        if [ ! -z $host ]
        then
                config[host]=$host
        fi
fi
# ========================================================================================================================================================================================

# validate once more we have an IP address to backup

if [[ -z ${config[host]} ]]
then
        echo "PRE-RUN CHECK FATAL ERROR] You MUST supply a router to backup"
        exit 255
fi
# ========================================================================================================================================================================================

# if the user has not set optional information on the command line nor in the config file, set known defaults

if [[ -z ${config[hostname]} ]]
then
        config[hostname]=$(ssh -i ${config[keyfile]} ${config[sshusr]}@${config[host]} "/system/identity/print" | cut -d ' ' -f 4 | tr -d '\r\n')

fi
if [[ -z ${config[backupfilename]} ]]
then
        if [[ -z $backupfilename ]]
        then
                config[backupfilename]="${config[hostname]}_$(date +${config[dateformat]})"
        fi
fi
if [[ -z ${config[logfile]} ]]
then
        if [[ -z $logfile ]]
        then
                config[logfile]="${config[hostname]}_$(date +${config[dateformat]})_backup.log"
        fi
fi
if [[ -z ${config[backuppath]} ]]
then
        config[backuppath]=$(pwd)
fi


# ========================================================================================================================================================================================

## script functions

logger () {
        echo "[MikroTik backup - $(date "+${config[dateformat]} ${config[timeformat]}") - ${config[hostname]}] $*"
}

error_handler() {
        if [[ $2 -gt 0 ]]
        then
                logger "Previous step ($1) failed, return code: $2, aborting!"
                case $1 in
                        "fetch_file")
                                logger "Fetching backups failed, deleting temporary files from $hostname"
                                remote_exec "/file/remove ${config[backupfilename]}.rsc"
                                remote_exec "/file/remove ${config[backupfilename]}.backup"
                                ;;
                        "logging")
                                echo "Make sure the following path exists and it's readable and writable: ${config[logfile]}"
                                ;;
                        "remote_exec")
                                echo "Make sure the host is reachable, you're using the right username and keyfile"
                                ;;
                        "local_exec")
                                echo "Local command execution failed"
                                ;;
                esac
                exit $2
        fi
}

remote_exec() {
        logger "Executing ssh -i ${config[keyfile]} ${config[sshusr]}@${config[host]} $*"
        ssh -i ${config[keyfile]} ${config[sshusr]}@${config[host]} $* || error_handler "remote_exec" $?
}

fetch_file() {
        logger "Executing sftp -i ${config[keyfile]} ${config[sshusr]}@${config[host]}:$1 $2"
        sftp -i ${config[keyfile]} ${config[sshusr]}@${config[host]}:$1 $2 || error_handler "fetch_file" $?
}

local_exec() {
        logger "Running $*"
        $* || error_handler "local_exec" $?
}

rotate_file() {
        logger "Checking if it's needed to rotate $1"
        if test -f $1
        then
                rotatetime=$(date "+${config[dateformat]}_${config[timeformat]//:/_}")
                logger "Rotating \"$1\""
                mv $1 $1.$rotatetime || error_handler rotate_file 100
                logger "Rotated \"$1\" as \"$1.$rotatetime\""
                local_exec ls -lha $1.$rotatetime
        else
                logger "No need to rotate $1, it doesn't exist yet."
        fi
}

# ========================================================================================================================================================================================


#rotate previous script log in case:
# - the script was already ran today and no log filename was provided
# - the log file name is static (usually used when SIEM or similar is involved)

if test -f ${config[logfile]}
then
        rotatetime=$(date "+${config[dateformat]}_${config[timeformat]//:/_}")
        mv ${config[logfile]} "${config[logfile]}.$rotatetime" || error_handler rotate_log 100
        touch ${config[logfile]} || error_handler rotate_log 100
        rotated[runlog]=true
        rotated[runlogname]=${config[logfile]}.$rotatetime
fi

# ========================================================================================================================================================================================

## redirect stderr, stdout to logfile

exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec 1>>${config[logfile]} 2>&1 || error_handler logging 200

# ========================================================================================================================================================================================

# let's rock

logger "Current date and time is: $(date +"${config[dateformat]} ${config[timeformat]}")"
if $noconf
then
        logger "No config file present, using stdin parameters"
else
        logger "Config file present at $conf, using it's contents."
        logger "Config file parameters"
        while read cfgl
        do
                if echo $cfgl | grep -F '=' &>/dev/null
                then
                        var=$(echo "$cfgl" | cut -d '=' -f 1)
                        varval=$(echo "$cfgl" | cut -d '=' -f 2)
                        logger "$var=$varval"
                fi
        done <$conf
fi
logger "My backup path is ${config[backuppath]}"
if ${rotated[runlog]}
then
        logger "\"Rotated ${config[logfile]}\" as \"${rotated[runlogname]}\""
        local_exec ls -lha ${rotated[runlogname]}
fi

# let's make sure if the filenames are static as well (backupfilename) we are not overwriting older backups

rotate_file "${config[backuppath]}/${config[backupfilename]}.backup" "backup"
rotate_file "${config[backuppath]}/${config[backupfilename]}.rsc" "rsc"
rotate_file "${config[backuppath]}/${config[backupfilename]}.log" "rtrlog"

# ========================================================================================================================================================================================

logger "The script will create the following files on ${config[hostname]}: \"${config[backupfilename]}.rsc\", \"${config[backupfilename]}.backup\" and \"${config[backupfilename]}.log.txt\""
logger "Started $host backup."
logger "Logging in as ${config[sshusr]} with the following SSH key file: ${config[keyfile]}"
logger "Generating configuration export."
remote_exec "/export file=\"${config[backupfilename]}.rsc\""
logger "Generating binary backup."
remote_exec "/system/backup/save name=\"${config[backupfilename]}.backup\""
logger "Exporting system logs"
remote_exec "/log/print file=\"${config[backupfilename]}.log\""
logger "Listing created files on device"
remote_exec "/file/print where name=\"${config[backupfilename]}.backup\""
remote_exec "/file/print where name=\"${config[backupfilename]}.rsc\""
remote_exec "/file/print where name=\"${config[backupfilename]}.log.txt\""
logger "Fetching config export to ${config[backuppath]}"
fetch_file "${config[backupfilename]}.rsc" ${config[backuppath]}
fetch_file "${config[backupfilename]}.backup" ${config[backuppath]}
fetch_file "${config[backupfilename]}.log.txt" "${config[backuppath]}/${config[backupfilename]}.log"
logger "Listing newly created files at \"${config[backuppath]}\""
local_exec ls -lha ${config[backuppath]}/${config[backupfilename]}.{log,rsc,backup}
logger "Deleting temporary backup files from ${config[hostname]}"
remote_exec "/file/remove \"${config[backupfilename]}.rsc\""
remote_exec "/file/remove \"${config[backupfilename]}.backup\""
remote_exec "/file/remove \"${config[backupfilename]}.log.txt\""
logger "Listing files on device"
remote_exec "/file/print"
