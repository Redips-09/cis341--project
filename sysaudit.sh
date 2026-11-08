#!/bin/bash

## cis 341 system health monitor and security auditing daemon
## main bash script 
## author hamza

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" ##this makes sure the script can always find necessary files
CONFIG_FILE="$SCRIPT_DIR/sysaudit.cfg"   


source "$SCRIPT_DIR/sysaudit_logger.sh" ##sysadut_logger contains the config file parser function load_config()
source "$SCRIPT_DIR/validator.sh" ## validator contains some validator functions for checking config variables
source "$SCRIPT_DIR/sysaudit_scanner.sh" ## contains basic script to run audit
source "$SCRIPT_DIR/sysaudit_ceiling.sh"

############################################################################################################################


usercheck() {
    local current_user #variable current user
    local authorized_users #variable for authorized users

    current_user=$(id -un) # get current user
    authorized_users=${AUTHORIZED_USERS//\"/} # retrieve authorized user list

    if [[ " $authorized_users " == *" $current_user "* ]]; then # if current user is in the authorized list, print verified user
        echo "Verified user: $current_user"
    else
        echo "ERROR: Unable to verify: $current_user" >&2 # otherwhise print error
        exit 2
    fi
}


delegate_user() {

        if [[ "$(id -un)" != "auditmanager" ]]; then #if current user is not auditmanager, print error 
                echo "Unauthorized Access"
                exit 2
        fi

        read -p "Enter username: " add_user # enter username to add to delegate

        if ! id "$add_user" &>/dev/null; then #if user does not exist
                echo "User not found"
                return 1
        fi

		 AUTHORIZED_USERS=${AUTHORIZED_USERS//\"/} # remove quotes from authorized users list

        if [[ " $AUTHORIZED_USERS " == *" $add_user "* ]]; then # if user is already in the authorized list, print error
                echo "User is already authorized"
                return 1
        fi

		AUTHORIZED_USERS="$AUTHORIZED_USERS $add_user" # add new user to authorized users list

		sed -i.bak "s|^AUTHORIZED_USERS=.*|AUTHORIZED_USERS=\"$AUTHORIZED_USERS\"|" "$CONFIG_FILE" # create backup of config file

		echo "User $add_user has been added to the authorized users list."
}

## helper for task 9: allow CLI flags to override the sysaudit.cfg values
apply_cli_overrides(){
	shift # skips the --run or --daemon 
	while [ $# -gt 0 ]; do
		if [ $# -lt 2 ]; then # every option needs a value after it, otherwise shift 2 fails and the loop never ends
			echo "Missing value for $1" >&2
			exit 1
		fi
		case "$1" in
			--interval)
				OLD_INTERVAL="$SCAN_INTERVAL_SECONDS" # the change is logged after init_log (task 5)
				SCAN_INTERVAL_SECONDS="$2"
				shift 2 ;;
			--max-disk)
				MAX_DISK_USAGE="$2"
				shift 2 ;;
			--audit-dir)
				AUDIT_DIR="$2"
				shift 2 ;;
			--log-file)
				LOG_FILE="$2"
				shift 2 ;;
			--log-level)
				LOG_LEVEL="$2"
				shift 2 ;;
			*)
				echo "Invalid Argument: $1" >&2
				exit 1 ;;
		esac
	done
}


## daemon function to run in daemon mode 

run_daemon(){
local loop_num=1 # so the first loop is logged as #1
while true; do
	log_scan_start "$loop_num"
	generate_audit
	check_disk_ceiling
	sleep "$SCAN_INTERVAL_SECONDS"
	loop_num=$((loop_num + 1))
done
}

## function just prints the usage file
show_help(){
	cat "$SCRIPT_DIR/usage.txt"
}

if [ $# -eq 0 ]; then ##checks args if none prints the help file with options etc
	show_help
	exit 0
fi

## case statement for argument handling 

case "$1" in 

	--delegate)
	load_config "$CONFIG_FILE" || exit $?
	delegate_user
	;;

	-h| --help)
	show_help
	;;
	--run)
	
	load_config "$CONFIG_FILE" || exit $?
	apply_cli_overrides "$@"
	usercheck
	response=$?

	validate_config 

	response=$?

	if [ "$response" -ne 0 ];then

	exit "$response"

	else

	init_log || exit $?
	if [ -n "$OLD_INTERVAL" ]; then log_sleep_change "$OLD_INTERVAL" "$SCAN_INTERVAL_SECONDS"; fi
	echo "CONFIGURATION LOADED SUCCESSFULLY! RUNNING ONE AUDIT CYCLE"

	fi
	log_scan_start 1
	generate_audit
	check_disk_ceiling
	;;
	--daemon)
	
	load_config "$CONFIG_FILE" || exit $?
	apply_cli_overrides "$@"
	usercheck

	response=$?

	validate_config

	response=$?

	if [ $response -ne 0 ];then

	exit "$response"

	else

	init_log || exit $?
	if [ -n "$OLD_INTERVAL" ]; then log_sleep_change "$OLD_INTERVAL" "$SCAN_INTERVAL_SECONDS"; fi
	echo "CONFIGURATION LOADED SUCCESSFULLY! RUNNING IN DAEMON MODE"

	fi

	run_daemon
	;;
	*)
	echo "INVALID ARGUMENT" >&2
	show_help
	exit 1
	;;
esac











