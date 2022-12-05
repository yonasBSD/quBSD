#!/bin/sh

get_msg_stat() { 
	# _message determines which feedback message to call.
	# Just call "none" in the case you want no message to match.
	# _pass_cmd is optional, and can be used to exit and/or show usage

   local _message
   local _pass_cmd

	_message="$1"
	_pass_cmd="$2"

	case "$_message" in
	_1) cat << ENDOFMSG
ENDOFMSG
	;;	
	esac

	case $_pass_cmd in 
		usage_0) usage ; exit 0 ;;
		usage_1) usage ; exit 1 ;;
		exit_0)  exit 0 ;;
		exit_1)  exit 1 ;;
		*) : ;;
	esac
}

usage() { cat << ENDOFUSAGE 

qb-stat: List status of all jails 

Usage: qb-stat [-c <column>] [-h]

   -c: (c)olumn to sort by
   -h: (h)elp: Outputs this help message

ENDOFUSAGE
}

