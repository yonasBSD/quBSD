#!/bin/sh

##########################  LIST OF FUNCTIONS  ###########################

# get_global_variables 
# get_user_response 
# stop_jail
# restart_jail
# define_ipv4_convention 
# get_used_ips 
# discover_open_ipv4
# check_isvalid_ipv4
# check_isqubsd_ipv4
# check_isvalid_root
# check_isvalid_template
# check_isvalid_tunnel
# check_isvalid_schg
# check_isvalid_seclvl
# check_isvalid_maxmem
# check_isvalid_cpuset

##################################################################################
#############################  GENERIC  FUNCTIONS  ###############################
##################################################################################

# Source error messages for library functions (jails) 
. /usr/local/lib/quBSD/msg-quBSD-j.sh

# Source error messages for library functions (VMs) 
. /usr/local/lib/quBSD/msg-quBSD-vm.sh

get_global_variables() {
	# Global config files, mounts, and datasets needed by most scripts 

	# Define variables for files
	QBDIR="/usr/local/etc/quBSD"
	QBCONF="${QBDIR}/quBSD.conf"
	JMAP="${QBDIR}/jailmap.conf"
	JCONF="/etc/jail.conf"
	QBLOG="/var/log/quBSD.log"
	
	# Remove blanks at end of line, to prevent bad variable assignments. 
	sed -i '' -e 's/[[:blank:]]*$//' $QBCONF 
	sed -i '' -e 's/[[:blank:]]*$//' $JMAP  

	# Get datasets, mountpoints; and define files.
   QBROOT_ZFS=$(sed -nE "s:quBSD_root[[:blank:]]+::p" $QBCONF)
	JAILS_ZFS="${QBROOT_ZFS}/jails"
	ZUSR_ZFS=$(sed -En "s/^zusr_dataset[[:blank:]]+//p" $QBCONF)
	M_JAILS=$(zfs get -H mountpoint $JAILS_ZFS | awk '{print $3}')
	M_ZUSR=$(zfs get -H mountpoint $ZUSR_ZFS | awk '{print $3}')
} 

get_user_response() {
	# Exits successfully if response is y or yes 
	# Assigns _response=true|false ; available to caller function 
	# Optional $1 input - `severe' ; which requires a user typed `yes'

	read _response
	
	# If flagged with positional parameter `severe' require full `yes' 
	if [ "$1" == "severe" ] ; then 
		case "$_response" in 
			yes|YES) return 0	;;
			*) return 1 ;;
		esac
	fi
	
	case "$_response" in 
		y|Y|yes|YES) return 0	;;

		# Only return success on positive response. All else fail
		*)	return 1 ;;						
	esac
}

##################################################################################
#####################  FUNCTIONS RELATED TO JAILS HANDLING #######################
##################################################################################

get_onjails(){
	# Prints a list of all jails that are currently running; or returns 1
	jls | awk '{print $2}' | tail -n +2 || return 1
}

restart_jail() {
	# Restarts jail. Passes postional parameters, so checks are not missed
	# Default behavior: If a jail is off, start it. 
	# Override default with $3="hold"

	# Positional params and func variables. $_action defaults to `return 1`
	local _jail ; _jail="$1"
	local _action ; _action="$2" ;  _action="${_action:=return 1}"
	local _hold ; 	_hold="$3"

	# No jail specified. 
	[ -z "$_jail" ] && eval "$_action" "_0" "jail"  && return 1

	# If the jail was off, and the hold flag was given, don't start it.
	! check_isrunning_jail "$_jail" && [ "$_hold" == "hold" ] && return 0

	# Otherwise, cycle jail	
	stop_jail "$_jail" "$_action" && start_jail "$_jail" "$_action"
}

start_jail() {
	# Performs required checks on a jail, starts if able, and returns 0.
	# Caller may pass positional: $2 , to dictate action on failure.
		# Default if no $2 provided, will return 1 silently.
	# _jf = jailfunction

	# Positional params and func variables. $_action defaults to `return 1`
	local _jail ; _jail="$1"
	local _action ; _action="$2" ;  _action="${_action:=return 1}"

	# Check that JAIL was provided in the first place
	[ -z "$_jail" ] && eval "$_action" "_0" "jail" && return 1

	# Check to see if _jail is already running 
	if	! check_isrunning_jail "$_jail" ; then

		# Run prelim checks on jail 
		if check_isvalid_jail "$_jail" "$_action" ; then
			
			# Checks were good, start jail, make a log of it 
			get_msg_qubsd "_jf1" "$_jail" | tee -a $QBLOG
			jail -c "$_jail"  >> $QBLOG  ||  eval "$_action" "_jf2" "$_jail"

		fi
	else
		# Jail was already on.
		return 0
	fi
}

stop_jail() {
	# If jail is running, remove it. Return 0 on success; return 1 if fail.	
	# Unfortunately, due to the way mounts are handled during jail -r, the
	# command will exit 1, even the jail was removed successfully. 
	# Extra logic has to be embedded to handle this problem.

	# Caller may pass positional: $2 , to dictate action on failure.
		# Default, or if no $2 provided, will return 1 silently.

	# Positional params and func variables. $_action defaults to `return 1`
	local _jail ; _jail="$1"
	local _action ; _action="$2" ;  _action="${_action:=return 1}"

	# Check that JAIL was provided in the first place
	[ -z "$_jail" ] && eval "$_action" "_0" "jail" && return 1

	# Check if jail is on, if so remove it 
	if check_isrunning_jail "$_jail" ; then	

		# TRY TO REMOVE JAIL NORMALLY 
		get_msg_qubsd "_jf3" "$_jail" | tee -a $QBLOG
		jail -vr "$_jail"  >> $QBLOG 
		
		# Extra logic to check if jail removal was successful 
		if check_isrunning_jail "$_jail" ; then 		

			# FORCIBLY REMOVE JAIL  
			get_msg_qubsd "_jf4" "$_jail" | tee -a $QBLOG
			jail -vR "$_jail"  >> $QBLOG 
			
			# Extra logic (same problem) to check jail removal success/fail 
			if check_isrunning_jail "$_jail" ; then 		

				# Print warning about failure to forcibly remove jail
				eval "$_action" "_jf5" "$_jail" 
			else
				# Run exec.poststop to clean up mounts, and print warning
				sh ${QBDIR}/exec.poststop "$_jail"
				get_msg_qubsd "_jf6" "$_jail" | tee -a $QBLOG
			fi
		fi
	else
		# Jail was already off. Not regarded as an error.
		return 0
	fi
}


##################################################################################
#######################  CHECKS ON JAILS and PARAMETERS  #########################
##################################################################################

## NOTES ON HOW CHECKS ARE BUILT
## Each check should be called from the main function with positional parameters:
	# $1={value_of_the_thing_to_check}
   # $2={_action} - The literal command that you want to execute if failure
		# `eval` is applied to $_action, so the variable becomes the command.
		# Default action is `return 1` (fail with no error message).
		# For error message: $2="get_msg_qubsd" is specified, which calls the
		# function:  get_msg_qubsd() ; from  /usr/local/lib/quBSD/msg-quBSD.sh
		# get_msg_qubsd also has positional parameters that should be specified. 
			# $1 uniquely identifies the msg to show from the case/in statement
         # $2 is an arbitrary "_passvar" which can be used in the message body.
				# This helps reduce total number of case/in elements in get_msg_qubsd()
			# $3 Is an optional action to take after printing message. 
				# This should be largely unused, but user may specify:
					# exit_0, exit_1, return_0, return_1  
	  				# If not provided, default is return_1

check_isrunning_jail() {
	# Return 0 if jail is running; return 1 if not. 

	# Positional params and func variables. $_action defaults to `return 1`
	local _value; _value="$1"  
	local _action ; _action="$2" ;  _action="${_action:=return 1}"

	# No jail specified. 
	[ -z "$_value" ] && eval "$_action" "_0" "jail" && return 1

	# Check if jail is running. No warning message returned if not.
	jls -j "$_value" > /dev/null 2>&1  || return 1 
}

check_isvalid_jail() {
	# Checks that jail has JCONF, JMAP, and corresponding ZFS dataset 
	# Return 0 if jail is running; return 1 if not. 

	# Positional parameters and func variables. $_action defaults to `return 1`
	local _value; _value="$1"  
	local _action ; _action="$2" ;  _action="${_action:=return 1}"
	local _class ; local _rootjail ; local _template

	# Fail if no jail specified
	[ -z "$_value" ] && eval "$_action" "_0" "jail" && return 1

	# Must have class in JMAP. Used later to find the correct zfs dataset 
	_class=$(sed -nE "s/^${_value}[[:blank:]]+class[[:blank:]]+//p" $JMAP)

	[ -z "$_class" ] && eval "$_action" "_cj1" "$_value" "class" && return 1
	# Must also have a designated rootjail in JMAP
	! grep -Eqs "^${_value}[[:blank:]]+rootjail[[:blank:]]+" $JMAP \
			&& eval "$_action" "_cj1" "$_value" "rootjail" && return 1

	# Jail must also have an entry in JCONF
	! grep -Eqs "^${_value}[[:blank:]]*\{" $JCONF \
			&& eval "$_action" "_cj3" && return 1

	# Verify existence of ZFS dataset
	case $_class in
		rootjail) 
			# Rootjails require a dataset at zroot/quBSD/jails 
			! zfs list ${JAILS_ZFS}/${_value} > /dev/null 2>&1 \
					&& eval "$_action" "_cj4" "$_value" "$JAILS_ZFS" && return 1
		;;
		appjail)
			# Appjails require a dataset at quBSD/zusr
			! zfs list ${ZUSR_ZFS}/${_value} > /dev/null 2>&1 \
					&& eval "$_action" "_cj4" "$_value" "$ZUSR_ZFS" && return 1
		;;
		dispjail)

			# Verify the dataset of the template for dispjail
			_template=$(sed -nE "s/^${_value}[[:blank:]]+template[[:blank:]]+//p"\
																								$JMAP)

			# First ensure that it's not blank			
			[ -z "$_template" ] && eval "$_action" "_cj5" "$_value" && return 1

			# Prevent infinite loop: $_template must not be a template for the  
			# jail under examination < $_value >. Otherwise, < $_value > would 
			# depend on _template, and _template would depend on < $_value >. 
			# However, it is okay for $_template to be a dispjail who's template 
			# is some other jail that is not < $_value >.
# NOTE: Technically speaking, this still has potential for an infinite loop, 
# but the user really has to try hard to create a circular reference.
			! check_isvalid_jail "$_template" "$_action" \
					&& eval "$_action" "_cj6" "$_value" "$_template" && return 1
		;;
			# Any other class is invalid
		*) eval "$_action" "_cj2" "$_class" "class"  && return 1
		;;
	esac
	return 0
}

check_isvalid_tunnel() {
	# Return 0 if proposed tunnel is valid ; return 1 if invalid

	# Positional parameters and func variables. $_action defaults to `return 1`
	local _value; _value="$1" 
	local _action ; _action="$2" ;  _action="${_action:=return 1}"
	local _jail; _jail="$3"  

	# net-firewall has special requirements for tunnel. Must be tap interface
##### NOTE: This isn't robust. It fails after tap0 to tap9
	[ "$_jail" == "net-firewall" ] && [ -n "${_value##tap[[:digit:]]}" ] \
			&& eval "$_action" "_cj7" "$_value" && return 1
	
	# `none' is valid for any jail except net-firewall. Order matters here.
	[ "$_value" == "none" ] && return 0

	# First check that tunnel is a valid jail. (note: func already has messages)  
 	check_isvalid_jail "$_value" "$_action" || return 1

	# Checks that tunnel starts with `net-'
	[ -n "${_value##net-*}" ] \
			&& eval "$_action" "_cj8" "$_value" "$_jail" && return 1

	return 0
}

check_isvalid_class() {
	# Return 0 if proposed schg is valid ; return 1 if invalid

	# Positional params and func variables. $_action defaults to `return 1`
	local _value; _value="$1"  
	local _action ; _action="$2" ;  _action="${_action:=return 1}"

	# No jail specified. 
	[ -z "$_value" ] && eval "$_action" "_0" "class"  && return 1

	# Valid inputs are: appjail | rootjail | dispjail 
	[ "$_value" != "appjail" ] && [ "$_value" != "rootjail" ] \
			&& [ "$_value" != "dispjail" ] \
					&& eval "$_action" "_cj2" "$_value" "class" && return 1
	return 0
}

check_isvalid_schg() {
	# Return 0 if proposed schg is valid ; return 1 if invalid

	# Positional params and func variables. $_action defaults to `return 1`
	local _value; _value="$1"  
	local _action ; _action="$2" ;  _action="${_action:=return 1}"

	# No value specified 
	[ -z "$_value" ] && eval "$_action" "_0" "schg" && return 1 

	# None is always a valid schg
	[ "$_value" == "none" ] && return 0 

	# Valid inputs are: none | sys | all
	[ "$_value" != "none" ] && [ "$_value" != "sys" ] \
			&& [ "$_value" != "all" ] \
					&& eval "$_action" "_cj2" "$_value" "schg" && return 1

	return 0
}

check_isvalid_seclvl() {
	# Return 0 if proposed seclvl is valid ; return 1 if invalid

	# Positional params and func variables. $_action defaults to `return 1`
	local _value; _value="$1"  
	local _action ; _action="$2" ;  _action="${_action:=return 1}"

	# No value specified 
	[ -z "$_value" ] && eval "$_action" "_0" "seclvl" && return 1

	# None is always a valid seclvl 
	[ "$_value" == "none" ] && return 0

	# Security defines levels from lowest == -1 to highest == 3
	[ "$_value" -lt -1 -o "$_value" -gt 3 ] \
			&& eval "$_action" "_cj2" "$_value" "seclvl" && return 1

	return 0
}

check_isvalid_maxmem() {
	# Return 0 if proposed maxmem is valid ; return 1 if invalid
# IMPROVEMENT IDEA - check that proposal isn't greater than system memory

	# Positional params and func variables. $_action defaults to `return 1`
	local _value; _value="$1"  
	local _action ; _action="$2" ;  _action="${_action:=return 1}"

	# No value specified 
	[ -z "$_value" ] && eval "$_action" "_0" "maxmem" && return 1

	# None is always a valid maxmem
	[ "$_value" == "none" ] && return 0
	
	# Per man 8 rctl, user can assign units: G|g|M|m|K|k
   ! echo "$_value" | grep -Eqs "^[[:digit:]]+(G|g|M|m|K|k)\$" \
			&& eval "$_action" "_cj2" "$_value" "maxmem" && return 1

	return 0
}

check_isvalid_cpuset() {
	# Return 0 if proposed schg is valid ; return 1 if invalid

	# Positional params and func variables. $_action defaults to `return 1`
	local _value; _value="$1"  
	local _action ; _action="$2" ;  _action="${_action:=return 1}"

	# No value specified 
	[ -z "$_value" ] && eval "$_action" "_0" "cpuset" && return 1

	# None is always a valid cpuset 
	[ "$_value" == "none" ] && return 0
	
	# Get the list of CPUs on the system, and edit for searching	
	_validcpuset=$(cpuset -g | sed "s/pid -1 mask: //" | sed "s/pid -1 domain.*//")

	# Test for negative numbers and dashes in the wrong place
	echo "$_value" | grep -Eq "(,-|,[[:blank:]]*-|^[^[:digit:]])" \
			&& eval "$_action" "_cj2" "$_value" "cpuset" && return 1

	# Remove `-' and `,' to check that all numbers are valid CPU numbers
	_cpuset_mod=$(echo $_value | sed -E "s/(,|-)/ /g")

	for _cpu in $_cpuset_mod ; do
		# Every number is followed by a comma except the last one
		! echo $_validcpuset | grep -Eq "${_cpu},|${_cpu}\$" \
			&& eval "$_action" "_cj2" "$_value" "cpuset" && return 1
	done

	return 0
}

check_isvalid_ipv4() {
	# Tests for validity of IPv4 CIDR notation.
	# return 0 if valid (or none), return 1 if not 

	# Variables below are required for caller function to perform other checks. 
	#   $_a0  $_a1  $_a2  $_a3  $_a4  

	# Positional params and local vars. $_action defaults to `return 1`
	local _value; _value="$1"  
	local _action ; _action="$2" ;  _action="${_action:=return 1}"
	local _b1 ; local _b2 ; local _b3
	
	# _jail only needed for net-firewall exception
	local _jail ; _jail="$3"

	# No value specified 
	[ -z "$_value" ] && eval "$_action" "_0" "IPv4" && return 1

	# None is always considered valid; but send warning for net-firewall
	[ "$_value" == "none" ] && return 0

	# Not as technically correct as a regex, but it's readable and functional 
	# IP represented by the form: a0.a1.a2.a3/a4 ; b-variables are local/ephemeral
	_a0=${_value%%.*.*.*/*}
	_a4=${_value##*.*.*.*/}
		b1=${_value#*.*}
		_a1=${b1%%.*.*/*}
			b2=${_value#*.*.*}
			_a2=${b2%%.*/*}
				b3=${_value%/*}
				_a3=${b3##*.*.*.}

	# Ensures that each number is in the proper range
	if echo "$_value" | grep -Eqs \
		"[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+/[[:digit:]]+"\
			 >> /dev/null 2>&1 ; then

		# Ensures that each digit is within the proper range 
		if    [ "$_a0" -ge 0 ] && [ "$_a0" -le 255 ] \
			&& [ "$_a1" -ge 0 ] && [ "$_a1" -le 255 ] \
			&& [ "$_a2" -ge 0 ] && [ "$_a2" -le 255 ] \
			&& [ "$_a3" -ge 0 ] && [ "$_a3" -le 255 ] \
			&& [ "$_a4" -ge 0 ] && [ "$_a4" -le 32 ]  >> /dev/null 2>&1
		then
			return 0
		else
			# Error message, is invalid IPv4
			eval "$_action" "_cj10" "$_value" && return 1
		fi

	else
		# Error message, is invalid IPv4
		eval "$_action" "_cj10" "$_value" && return 1
	fi
}

check_isqubsd_ipv4() {
	# Checks for IP overlaps and/or mismatch in quBSD convention. 
	# Assigns the following, available to caller function:
		# $_isoverlap=true
		# $_ismismatch=true

	# Positional params and func variables. $_action defaults to `return 1`
	local _value  ; _value="$1"  
	local _action ; _action="$2" ;  _action="${_action:=return 1}"
	local _jail   ; _jail="$3" 
	
	define_ipv4_convention
	_used_ips=$(get_used_ips)

	# No value specified 
	[ -z "$_value" ] && eval "$_action" "_0" "IPv4" 

	# net-firewall needs special attention
	if [ "$_jail" == "net-firewall" ] ; then 

		# IP0 `none' with net-firewall shouldn't really happen
		[ "$_value" == "none" ] \
					&& eval "$_action" "_cj9" "$_value" "$_jail" && return 1
	
		# All else gets ALERT message
		eval "$_action" "_cj15" "$_value" "$_jail" && return 1
	fi

	# IP0 `none' with < net- > jails should also be rare/never 
	[ "$_value" == "none" ] && [ -z "${_jail##net-*}" ] \
					&& eval "$_action" "_cj13" "$_value" "$_jail" && return 1
	
	# Otherwise, `none' is fine for any other jails. Skip additional checks.
	[ "$_value" == "none" ] && return 0 

	# Compare against JMAP, and _USED_IPS 
	if grep -qs "$_value" $JMAP \
			|| [ $(echo "$_used_ips" | grep -qs "${_value%/*}") ] ; then
	
		eval "$_action" "_cj11" "$_value" "$_jail" && return 1
	fi

	# Note that $a2 and $ip2 are missing, because that is the _cycle 
	# Any change to quBSD naming convention will require manual change.
	! [ "$_a0.$_a1.$_a3/$_a4" == "$_ip0.$_ip1.$_ip3/$_subnet" ] \
			&& eval "$_action" "_cj12" "$_value" "$_jail" && return 1

	_tunnel=$(sed -nE "s/^${_jail}[[:blank:]]+tunnel[[:blank:]]+//p" $JMAP)
	[ "$_tunnel" == "none" ] && eval "$_action" "_cj14" "$_value" "$_jail" \
		&& return 1
	
	# Otherwise return 0
	return 0
}


##################################################################################
#######################  FUNCTIONS RELATED TO NETWORKING #########################
##################################################################################

define_ipv4_convention() {
	# Defines the quBSD internal IP assignment convention.
	# Variables: $ip0.$ip1.$ip2.$ip3/subnet ; are global, required 
	# for functions:  discover_open_ipv4() and check_isqubsd_ipv4() 

	# Returns 0 for any normal IP assignment, returns 1 if 
	# operating on net-firewall (which needs special handling).

	# Variable indirection is used with `_cycle', in discover_open_ipv4() 
	_cycle=1

	# Combo of function caller and $JAIL determine which IP form to use
	case "$0" in
		*qb-connect)
				# Temporary, adhoc connections have the form: 10.99.x.2/30 
				_ip0=10 ; _ip1=99 ; _ip2="_cycle" ; _ip3=2 ; _subnet=30 ;;

		*qb-usbvm)
				# usbvm connects to usbjail with the address: 10.77.x.2/30 
				_ip0=10 ; _ip1=77 ; _ip2="_cycle" ; _ip3=2 ; _subnet=30 ;;

		*) case $JAIL in
				net-firewall) 	
					# firewall IP is not internally assigned, but router dependent. 
					_cycle=256 ; return 1 ;;

				net-*)	
					# net jails IP address convention is: 10.255.x.2/30  
					_ip0=10 ; _ip1=255 ; _ip2="_cycle" ; _ip3=2 ; _subnet=30 ;;

				serv-*)  
					# Server jails IP address convention is: 10.128.x.2/30  
					_ip0=10 ; _ip1=128 ; _ip2="_cycle" ; _ip3=2 ; _subnet=30 ;;

				*)	
					# All other jails should receive convention: 10.1.x.2/30 
					_ip0=10 ; _ip1=1 ; _ip2="_cycle" ; _ip3=2 ; _subnet=30 ;;
			esac
	esac
}

get_used_ips() {
	# Gathers a list of all IP addresses in use by running jails.
	# Assigns variable: $_used_ips for use in main script. This variable
	# is unfiltered, containing superflous info from `ifconfig` command.
	
	# Assemble list of ifconfig inet addresses for all running jails
	for _jail in $(get_onjails) ; do
		_intfs=$(jexec -l -U root $_jail ifconfig -a inet | grep "inet")
		_USED_IPS=$(printf "%b" "$_USED_IPS" "\n" "$_intfs")
	done
}

discover_open_ipv4() {	
	# Finds an IP address unused by any running jails, or in jailmap.conf 
	# Echo open IP on success; Returns 1 if failure to find an available IP

	# Positional params and func variables. $_action defaults to `return 1`
	local _value; _value="$1"  
	local _action ; _action="$2" ;  _action="${_action:=return 1}"
	local _temp_ip

	# net-firewall connects to external network. Assign DHCP, and skip checks. 
	[ "$_value" == "net-firewall" ] && echo "DHCP" && return 0

	# _used_ips checks IPs in running jails, to compare each _cycle against 
	local _used_ips ; _used_ips=$(get_used_ips)
		
	# Assigns values for each IP position, and initializes $_cycle
	define_ipv4_convention
	
	# Increment _cycle to find an open IP. 
	while [ $_cycle -le 255 ] ; do

		# $_ip2 uses variable indirection, which subsitutes "cycle"
		eval "_temp_ip=${_ip0}.${_ip1}.\${$_ip2}.${_ip3}"

		# Compare against JMAP, and the IPs already in use
		if grep -qs "$_temp_ip" $JMAP	\
					|| [ $(echo "$_used_ips" | grep -qs "$_temp_ip") ] ; then

			# Increment for next cycle
			_cycle=$(( _cycle + 1 ))

			# Failure to find IP in the quBSD conventional range 
			if [ $_cycle -gt 255 ] ; then 
				eval "_pass_var=${_ip0}.${_ip1}.x.${_ip3}"
				eval "$_action" "_ip1" "$_value" "$_pass_var"
				return 1
			fi
		else
			# Echo the value of the discovered IP and return 0 
			echo "${_temp_ip}/${_subnet}" && return 0
		fi
	done
}

remove_tap() {
	# If TAP is not already on host, find it and bring it to host
	# Return 1 on failure, otherwise return 0 (even if tap was already on host)

	# Assign name of tap
	[ -n "$1" ] && _tap="$1" || return 1
	
	# Check if it's already on host
	ifconfig "$_tap" > /dev/null 2>&1  &&  return 0
	
	# First find all jails that are on
	for _jail in $(get_onjails) ; do
		if `jexec -l -U root $o ifconfig -l | egrep -qs "$tap"` ; then
			ifconfig $tap -vnet $o
			ifconfig $tap down
		fi
	done

	# Bring tap down for host/network safety 
	ifconfig $_tap down 
}


##################################################################################
#######################  FUNCTIONS RELATED TO VM HANDLING ########################
##################################################################################

check_isrunning_vm() {
	# Return 0 if bhyve VM is a running process; return 1 if not.	
	
	local _VM
	[ -n "$1" ] && _VM="$1" || return 1 

	pgrep -qf "bhyve: $_VM"  >>  /dev/null 2>&1  ||  return 1
}

poweroff_vm() {
	# Tries to gracefully shutdown VM with SIGTERM, as per man bhyve
	# Monitor process for 90 seconds. return 0 if removed, 1 if timeout 
	# Pass option "quiet" if no stdout is desired

	local _vm
	local _count		
	local _quiet

	local _vm
	[ -n "$1" ] && _vm="$1" || eval "$_action _0 $2" 
	local _action
	# Action to take on failure. Default is return 1 to caller function
	[ -z "$2" ] && _action="return 1" || _action="return 1"

	# Error if $_jail provided is empty
	[ -z "$_jail" ] && 

	[ -n "$1" ] && _VM="$1" || return 1 
	[ "$2" == "quiet" ] && _quiet="true" 
	
	# pkill default is SIGTERM (-15) 
	pkill -f "bhyve: $_VM"  && get_msg_qb_vm "_3"

	# Monitor for VM shutdown, via process disappearance
	_count=1
	while check_isrunning_vm "$_VM" ; do
		
		# Prints	a period every second
		[ -z "$quiet" ] && sleep 1 && get_msg_qb_vm "_4"

		_count=$(( count + 1 ))
		[ "$_count" -gt 30 ] && get_msg_qb_vm "_5" "exit_1"
	done

}

testfunct() {
	local _cpuset ; _cpuset="$1"  
	local _action ; _action="$2" ;  _action=${_action:=return 1}

	get_msg "_vj11" "testest"

	echo but were doing more stuff how it work now?
	
}










