# RouterOS Backup

A bash script to automate your MikroTik backup needs.

## Configuration

The following options can be specified in the configuration file:
- `sshusr`: the user's name that exists on the router for backup purposes
- `keyfile`: the full path to the SSH private key file
- `dateformat`: the date format that will be used in logs and backup names
- `timeformat`: the time format that will be used in logs
- `backuppath`: full path where backups will be stored
- `logfile`: full path to the log file that will be written to
- `host`: what to connect to through SSH
- `hostname`: in case you use different naming conventions for backups compared to what you have set on the router with `/system/identity`

```
sshusr=<mikrotik_ip>
keyfile=</path/to/ssh_private_key>
dateformat=%Y-%m-%d
timeformat=%H:%M:%S
backuppath=/path/to/directory/where/backup/should/be/stored
logfile=/path/to/logfile.log
host=<mikrotikip>
hostname=<mikrotikneve>

```

## Automation

Use cron jobs, like this:

```
50 23 * * * /usr/local/bin/mikrotik_backup.sh -c /etc/mikrotik_backup/ny01.conf
```