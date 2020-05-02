#!/bin/bash
set -e
VERSION=0.0.1
command=$1
friendlyName=$2
arg3=$3

current_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# SO: https://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux
RED='\033[0;31m'
GRAY='\033[90m'
CYAN='\033[96m'
NC='\033[0m' # No Color

echo "$command"
case $command in
    startup|connect|sftp|sshfs|bind|stop)

    # this file should have instance_id and pathToPrivateKey
    # lets check if the entered name is correct
    instanceFilenames=$(ls $current_dir/.*_instance)
    correct_name=false
    for filename in $instanceFilenames; do
        friendlyNameFound=$(echo $filename | sed 's/\.//' | sed  "s~$current_dir/~~" | sed "s/_instance//")
        if [[ "$friendlyName" == "$friendlyNameFound" ]]
            then correct_name=true;
        fi
    done

    if [ "$correct_name" != true ]
        then
        echo -e "${RED}friendly name of${NC} ${GREEN}"$friendlyName"${NC} ${RED} not found (did you spell it right?)"
        echo -e "\t use 'ezws.sh list' to see a list of available friendly names${NC}"
        exit
    fi

    instance_id=$(cat "$current_dir/.$friendlyName"_instance)
    pathToPrivateKey=$(cat "$current_dir/.$friendlyName"_key)
    profile=$(cat "$current_dir/.$friendlyName"_profile)
        ;;
    add|list|reindex) # do nothing
        ;;
    *) # print help
       echo "ezws.sh version $VERSION"
       echo -e "${RED}invalid command option${NC}"
       echo "listing available commands:"
       echo "    add: add instance and key to registered machines"
       echo "    list: list out all instances friendly names and ids"
       echo "    connect: ssh to an already running instance"
       echo "    startup: start a aws instance and ssh to it"
       echo "    stop: stop a running instance"
       echo "    sftp: sftp to an already running instance"
       echo "    sshfs: use sshfs to mount the root directory (default) or a specified directory (command line argument) of an already running instance to the cwd"
       echo "    bind: bind a port to an already running instance"
       echo "    reindex: add all the added machines to tab completion"
       echo "exiting"
       exit
    ;;
esac


describe() {
    # echo is how we are returning a string value
    # first case, catches if the time-clock is out of sync
    # second case is the typical behavior
    output=$(aws ec2 describe-instances "$@")
    if [[ $output == *"An error occurred (AuthFailure) when calling the DescribeInstances operation: AWS was not able to validate the provided access credentials"* ]]; then
        # see this link for more info: https://webcache.googleusercontent.com/search?q=cache:K4H2wZL_tfIJ:https://forums.aws.amazon.com/thread.jspa%3FmessageID%3D722197
        echo -e "${RED}[error]${NC} your clock is out of sync please run the following command, then try again">&2
        echo -e 'sudo date -s "$(wget -qSO- --max-redirect=0 google.com 2>&1 | grep Date: | cut -d' ' -f5-8)Z"'>&2
        return 1
    fi
    echo $output
}

case $command in
    startup)
        aws ec2 start-instances --instance-ids $instance_id --profile $profile

        #wait until the node is up and running
        node_stopped=true
        while $node_stopped; do
            sleep 0.5s
            state="$(describe --instance-ids $instance_id --query 'Reservations[*].Instances[*].State.Name' --output text --profile $profile)"
            if [ "$state" = "running" ]
                then node_stopped=false; sleep 2s;
            fi
        done

        ;;
    connect)


        state="$(describe --instance-ids $instance_id --query 'Reservations[*].Instances[*].State.Name' --output text --profile $profile)"
        if [ "$state" != "running" ]
            then echo "machine not running"; exit;
        fi

        #grab the public ip address from aws
        publicIpAddress="$(describe --instance-ids $instance_id --query 'Reservations[*].Instances[*].PublicIpAddress' --output text --profile $profile)"

        #add node to known hosts (skip fingerprint question)
        ssh-keyscan -H $publicIpAddress >> ~/.ssh/known_hosts

        # add key to ssh-agent to enable key forwarding
        case "$(uname -s)" in
            Linux*) ssh-add $pathToPrivateKey;;
            Darwin*) ssh-add -K $pathToPrivateKey;;
            *) echo -e "${RED}[warning]${NC} unrecognized OS. SSH key not automatically added to agent. Use `ssh-add` to add your private key to ssh agent for ssh key forwarding"
        esac


        #connect to node
        echo $publicIpAddress
        ssh -A -i $pathToPrivateKey ubuntu@$publicIpAddress
        ;;
    bind)

        state="$(describe --instance-ids $instance_id --query 'Reservations[*].Instances[*].State.Name' --output text --profile $profile)"
        if [ "$state" != "running" ]
            then echo "machine not running"; exit;
        fi

        #connect to node
        localPort=$3
        remotePort=$4

        #grab the public ip address from aws
        publicIpAddress="$(describe --instance-ids $instance_id --query 'Reservations[*].Instances[*].PublicIpAddress' --output text --profile $profile)"

        case $localPort in
            [0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9]) #just check if it is a 4- or 5-digit number
                # echo "valid local port"
                ;;
            *)
                echo "invalid local port"
                echo "exiting"
                exit
                ;;
        esac
        case $remotePort in
            [0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9]) #just check if it is a 4- or 5-digit number
                # echo "valid remote port"
                ;;
            *)
                echo "invalid remote port"
                echo "exiting"
                exit
                ;;
        esac

        echo "binding port $localPort to $publicIpAddress:$remotePort"

        ssh -N -f -L localhost:$localPort:localhost:$remotePort ubuntu@$publicIpAddress -i $pathToPrivateKey

        ;;
    sftp)

        state="$(describe --instance-ids $instance_id --query 'Reservations[*].Instances[*].State.Name' --output text --profile $profile)"
        if [ "$state" != "running" ]
            then echo "machine not running"; exit;
        fi

        #grab the public ip address from aws
        publicIpAddress="$(describe --instance-ids $instance_id --query 'Reservations[*].Instances[*].PublicIpAddress' --output text --profile $profile)"


        #connect to node
        echo $publicIpAddress
        sftp -i $pathToPrivateKey ubuntu@$publicIpAddress
        ;;
    sshfs)

        state="$(describe --instance-ids $instance_id --query 'Reservations[*].Instances[*].State.Name' --output text --profile $profile)"
        if [ "$state" != "running" ]
            then echo "machine not running"; exit;
        fi

        #grab the public ip address from aws
        publicIpAddress="$(describe --instance-ids $instance_id --query 'Reservations[*].Instances[*].PublicIpAddress' --output text --profile $profile)"


        #connect to node
        echo $publicIpAddress
        sshfs ubuntu@$publicIpAddress:/$arg3 . -o IdentityFile=$pathToPrivateKey
        ;;
   stop)

       read -r -p "Are you sure no one else is using this machine? [y/n] " response
       case "$response" in
           [yY][eE][sS]|[yY])
               aws ec2 stop-instances --instance-ids $instance_id --profile $profile
               ;;
           *)
               echo "stopping operation cancelled - $instance_id is still running!"
               exit
               ;;
       esac
       ;;
   add)
       #  look for private key and get the oldest one
       oldestPrivateKey=$(ls -t ~/.ssh/*.pem | tail -1)
       read -r -p "enter a friendly name for this instance: " friendlyName
       read -r -p "enter the instance id: " instance_id
       read -r -p "enter the path to the private ssh key: [$oldestPrivateKey]" pathToPrivateKey
       read -r -p "enter profile: [default] " profile
       profile=${profile:-default}
       pathToPrivateKey=${pathToPrivateKey:-$oldestPrivateKey}

       # save info to files
       echo "$instance_id" > "$current_dir/.$friendlyName"_instance
       echo "$pathToPrivateKey" > "$current_dir/.$friendlyName"_key
       echo "$profile" > "$current_dir/.$friendlyName"_profile
       echo ".$friendlyName*" >> $current_dir/.gitignore

       # add friendly name to tab completer
       sed -i'' -e "/local hostname/ s/\"$/ $friendlyName\"/" $current_dir/bash_completion.d/ezws.sh
       echo "done please resource your ~/.bashrc (Linux) or ~/.bash_profile (Mac OS) to use the updated tab completion"

       ;;
   list)
       instanceFilenames=$(ls $current_dir/.*_instance)
       for filename in $instanceFilenames; do
           friendlyName=$(echo $filename | sed 's/\.//' | sed  "s~$current_dir/~~" | sed "s/_instance//")
           profile=$(cat "$current_dir/.$friendlyName"_profile)
           state="$(describe --instance-ids $(cat $filename) --query 'Reservations[*].Instances[*].State.Name' --output text --profile $profile)"
            if [ "$state" != "running" ]; then
                echo -e "$(echo $friendlyName: $(cat $filename)) ${GRAY} (not running) ${NC}"
            else
                echo -e "$(echo $friendlyName: $(cat $filename)) ${CYAN} (running) ${NC}"
            fi
        done
       ;;
   reindex)
       instanceFilenames=$(ls $current_dir/.*_instance)
       for filename in $instanceFilenames; do
           friendlyName=$(echo $filename | sed 's/\.//' | sed  "s~$current_dir/~~" | sed "s/_instance//")
           # add friendly name to tab completer
           sed -i'' -e "/local hostname/ s/\"$/ $friendlyName\"/" $current_dir/bash_completion.d/ezws.sh
        done
        echo "done please resource your ~/.bashrc (Linux) or ~/.bash_profile (Mac OS) to use the updated tab completion"
       ;;
   *)
       ;;
    esac
