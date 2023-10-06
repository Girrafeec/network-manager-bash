#!/bin/bash

# Exit 
exitScript() {
	clear
	exit 0
}

showAdapters() {
	network_json_data=$(sudo lshw -class network -json 2> /dev/null)

	# Check if the command was successful
	if [ $? -ne 0 ]; then
		# Print an error message if the command failed
		dialog --title "Error" --msgbox "Unable to retrieve adapters list" 10 40
		showMainMenu
	else
		ip_message=""
	  	# Iterate through network cards in JSON and print their information
	  	message=$(echo "$network_json_data" | jq -r '.[] | "\nDescription:  \(.description)\nProduct:  \(.product)\nVendor:  \(.vendor)\nLogical name:  \(.logicalname)\nMAC:  \(.serial)\nDuplex:  \(.configuration.duplex)\nSpeed:  \(.configuration.speed)\nLink:  \(.configuration.link)\n---"')
	  
	  	# Extract the list of logical names from JSON
	  	logical_names=$(echo "$network_json_data" | jq -r '.[].logicalname')

		# Iterate through network cards and add IP and Mask info to the message
		for logical_name in $logical_names; do
			ip_info=$(sudo ifconfig $logical_name | grep "inet " | awk '{print $2}')
		      	mask_info=$(sudo ifconfig $logical_name | grep "netmask " | awk '{print $4}')
		      	gateway_info=$(sudo ip route show dev $logical_name | awk '/default/ {print $3}')
		      	dns_address=$(sudo grep "^nameserver" /etc/resolv.conf | awk '{print $2}')
#		      	if [ -n "$ip_info" ]; then
				ip_message+="
				
				Logical Name: $logical_name
				IP: $ip_info
				Mask: $mask_info
				Gateway: $gateway_info
				DNS: $dns_address"
#		      	fi
		done
		
		dialog --title "Network adapters" --msgbox "$message $ip_message" 30 80 
		  
		case $? in
			# Ok
        		0)
                        	showMainMenu;;
        		# ESC
			255)
                        	showMainMenu;;
		esac
	fi
}

staticAdapterConfig() {
	adapter=$1

	tempfile=`mktemp 2>/dev/null` || tempfile=/tmp/test$$
	trap "rm -f $tempfile" 0 1 2 5 15
	
	dialog --clear --title "Adapter configuration" \
	 	--form "Enter parameters for $adapter_name adapter:" 15 60 4 \
 		"IP-address:" 1 1 "" 1 20 32 0 \
         	"Mask:" 2 1 "" 2 20 32 0 \
         	"Gateway address:" 3 1 "" 3 20 32 0 \
         	"DNS-address:" 4 1 "" 4 20 32 0 2> $tempfile
         	
        mapfile -t user_input < $tempfile	
	
	# Remove the tempfile
	rm -f tempfile
	
	ip_address="${user_input[0]}"
	mask="${user_input[1]}"
	gateway="${user_input[2]}"
	dns="${user_input[3]}"
	
	sudo ifconfig $adapter $ip_address netmask $mask
	sudo route add default gw $gateway
	sudo echo "nameserver $dns" | sudo tee /etc/resolv.conf > /dev/null
	
	dialog --msgbox "$adapter adapter successfully configured." 10 30
	showMainMenu
}

dynamicAdapterConfig() {
	adapter=$1
	sudo dhclient -v $adapter 2>&1 | dialog --clear --title "Adapter $adapter configuration" --progressbox 10 50
        if [ $? -eq 0 ]; then
           		dialog --msgbox "$adapter adapter successfully configured." 10 30
        else
            	dialog --clear --msgbox "Dynamic configuration error" 10 30
        fi
        showMainMenu	
}

showAdapterSetupMenu() {
	network_json_data=$(sudo lshw -class network -json 2> /dev/null)
	# Extract the list of logical names from JSON
	logical_names=$(echo "$network_json_data" | jq -r '.[].logicalname')
	
	tempfile=`mktemp 2>/dev/null` || tempfile=/tmp/test$$
	trap "rm -f $tempfile" 0 1 2 5 15

	# Create an array to hold menu items
	menu_items=()
	    
	# Populate the menu_items array with logical names
	for logical_name in $logical_names; do
		menu_items+=("$logical_name" "Adapter $logical_name")
	done

	dialog --clear --title "Network adapters" \
        	--menu "Choose network adapter to setup" 15 50 3 "${menu_items[@]}" 2> $tempfile

	retval=$?

	choosed_adapter=`cat $tempfile`

	# Remove the tempfile
	rm -f tempfile

	case $retval in
		# Ok
   	 	0)
                	;;
               	# Cancel
        	1)
                	showMainMenu;;
        	# ESC
		255)
                        showMainMenu;;
	esac
	
	tempfile=`mktemp 2>/dev/null` || tempfile=/tmp/test$$
	trap "rm -f $tempfile" 0 1 2 5 15
	
	dialog --clear --title "$choosed_adapter adapter configuration" --menu "Choose configuration" 15 60 4 \
		   1 "Static"\
		   2 "Dynamic"\
		   2> $tempfile
	
		retval=$?

	choosed_configuration=`cat $tempfile`

	# Remove the tempfile
	rm -f tempfile

	case $retval in
		# Ok
   	 	0)
                	;;
               	# Cancel
        	1)
                	showAdapterSetupMenu;;
        	# ESC
		255)
                        showAdapterSetupMenu;;
	esac
	
	case $choosed_configuration in
               	1)
                	staticAdapterConfig $choosed_adapter;;
                2)
                	dynamicAdapterConfig $choosed_adapter;;
       	esac	  		   
}

# Main menu
showMainMenu() {

	tempfile=`mktemp 2>/dev/null` || tempfile=/tmp/test$$
	trap "rm -f $tempfile" 0 1 2 5 15

	dialog --clear --title "Network manager" \
        	--menu "Choose network manager option" 20 50 3 \
        	1 "Network adaper list" \
        	2 "Setup network adapter" \
        	3 "Exit network manager" 2> $tempfile

	retval=$?

	choice=`cat $tempfile`

	case $retval in
        	0)
                	;;
        	# Cancel
        	1)
                        showExitMessage
                        exitScript;;
        	# ESC
		255)
                        showExitMessage
                        exitScript;;
	esac

        case $choice in
               	1)
                       	showAdapters;;
                2)
                	showAdapterSetupMenu;;
               	3)
                        exitScript;;
       	esac

}

# Package installing
installPackage() {
	apt-get -y install $1 2>&1 | dialog --clear --title "Installing $1" --progressbox 10 50
}

# Package checking
checkPackage() {
	PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $1 | grep "install ok installed")
}

# Check command
checkCommand() {
	CMD_OK=$(command -v $1)
	echo "0"
}

# Script start point

# Install dialog
DIALOG_PKG="dialog"
checkPackage $DIALOG_PKG
if [ "" = "$PKG_OK" ]; then
        apt-get install -y $DIALOG_PKG
fi

# net-tools
NET_TOOLS_PKG="net-tools"
checkPackage $NET_TOOLS_PKG
if [ "" = "$PKG_OK" ]; then
	installPackage $NET_TOOLS_PKG
fi

# lshw
LSHW_CMD="lshw"
checkCommand $LSHW_PKG
if [ "" = "$CMD_OK"  ] ; then
	installPackage $LSHW_CMD
fi

# jq
JQ_CMD="jq"
checkCommand $JQ_PKG
if [ "" = "$CMD_OK"  ] ; then
	installPackage $JQ_CMD
fi

showMainMenu
