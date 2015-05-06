#!/bin/bash -l

# Copyright (C) 2015 Codewerft Flensburg (http://www.codewerft.net)
# Licensed under the MIT License
#
# Leech is a simple bash script that periodically updates a locally
# cloned Git repository.

# -----------------------------------------------------------------------------
# Global variables
#
SCRIPTNAME=$(basename "$0")
SCRIPTVERSION=0.1
UPDATE_INTERVAL=30 # default interval - 30 seconds
CHECKOUT_DIR=
REPOSITORY_URL=
BRANCH=master # default branch is master
COMMAND=
ACTIVE_PID=0
TERMINATE=1

# -----------------------------------------------------------------------------
# Some ANSI color definitions
#
CLR_ERROR='\033[0;31m'
CLR_WARNING='\033[0;33m'
CLR_OK='\033[0;32m'
CLR_RESET='\033[0m'

# -----------------------------------------------------------------------------
# Print version of this tool
#
version()
{
    echo -e "\n$SCRIPTNAME $SCRIPTVERSION\n"
    echo -e "Copyright (C) 2015 Codewerft Flensburg (http://www.codewerft.net)"
    echo -e "Licensed under the MIT License\n"
    echo -e "This is free software: you are free to change and redistribute it."
    echo -e "There is NO WARRANTY, to the extent permitted by law.\n"
}

# -----------------------------------------------------------------------------
# Print the log prefix consisting of timestamp and scriptname
#
log_prefix()
{
    echo "[$(date +"%d/%b/%Y:%H:%M:%S %z")] $SCRIPTNAME:"
}

# -----------------------------------------------------------------------------
# Print script usage help
#
usage()
{

cat << EOF
usage: $SCRIPTNAME options

$SCRIPTNAME is a simple bash script that periodically updates a locally
cloned Git repository.

OPTIONS:

   -d DIR      Local direcotry to check out the repository to (workdir)
   -r URL      Git repository URL
   -b BRANCH   Branch to check out (default: master)
   -c COMMAND  Execute COMMAND after a change was detected
   -i INTERVAL Update interval (default: 5m)
   -v          Print the version of $SCRIPTNAME and exit.
   -h          Show this message


EXAMPLES:

  Clone and periodially update the 'release' branch of the 'leech' repository
on GitHub to /var/repos/leech:

$SCRIPTNAME -d /tmp/leech -r git@github.com:codewerft/leech.git -b release

EOF
}

# -----------------------------------------------------------------------------
# Launch the 'user command', set trap, record the pid
#
run_user_command()
{
  $COMMAND 2>&1 &
  ACTIVE_PID=$!
  trap 'pkill -2 -P $ACTIVE_PID; echo -e "$CLR_OK$(log_prefix) terminated all background processes on exit$CLR_RESET"; exit' SIGHUP SIGINT SIGTERM
  echo -e "$CLR_OK$(log_prefix) launched command '$COMMAND' with pid $ACTIVE_PID$CLR_RESET" >&2
}

# -----------------------------------------------------------------------------
# Terminate the 'user command'
#
terminate_user_command()
{
  # CPIDS=$(pgrep -P $ACTIVE_PID);
  # kill -KILL $CPIDS
  # only if the -t flag was provided
  if [ $ACTIVE_PID -ne 0 ]; then
    if ! pkill -2 -P $ACTIVE_PID > /dev/null 2>&1; then
      echo -e "$CLR_WARNING$(log_prefix) couldn't terminate process with pid $ACTIVE_PID (already dead)$CLR_RESET" >&2
    else
      echo -e "$CLR_OK$(log_prefix) successfully terminated process with pid $ACTIVE_PID$CLR_RESET" >&2
    fi
  fi
}

# -----------------------------------------------------------------------------
# Print script usage help
#
remote_has_changed()
{
    # update the tracking branches
    git remote update
    #
    LOCAL=$(git rev-parse @)
    REMOTE=$(git rev-parse @{u})
    BASE=$(git merge-base @ @{u})

    if [ $LOCAL = $REMOTE ]; then
        return 0
    else
        return 1
    fi
}

git_update()
{
    git pull
}

# -----------------------------------------------------------------------------
# MAIN - Script entry point
#

while getopts hvd:r:b:c:i: OPTION
do
    case $OPTION in
        h)
            usage
            exit 1
            ;;
        v)
            version
            exit 0
            ;;
        r)
            REPOSITORY_URL=$OPTARG
            ;;
        d)
            CHECKOUT_DIR=$OPTARG
            ;;
        b)
            BRANCH=$OPTARG
            ;;
        c)
            COMMAND=$OPTARG
            ;;
        i)
            UPDATE_INTERVAL=$OPTARG
            ;;
        ?)
            usage
            exit
            ;;
     esac
done

# Make sure at least -d and -r were set.
if [[ -z $CHECKOUT_DIR ]] || [[ -z $REPOSITORY_URL ]] || [[ -z $COMMAND ]]
then
    usage
    exit 1
fi


# Make sure the checkout dir exists and we have write permission.
if ! [[ -d "$CHECKOUT_DIR" ]] ; then
    echo -e "$CLR_OK$(log_prefix) creating checkout directory $CHECKOUT_DIR $CLR_RESET" >&2
    mkdir -p "$CHECKOUT_DIR"
fi

# Check if $CHECKOUT_DIR is a valid git repository.
cd "$CHECKOUT_DIR"
git status
if [[ $? != 0 ]] ; then
    # It is not. Clone the repository.
    echo -e "$CLR_WARNING$(log_prefix) no git reposiory found in $CHECKOUT_DIR. Cloning into $REPOSITORY_URL $CLR_RESET" >&2

    git clone -b "$BRANCH" "$REPOSITORY_URL" "$CHECKOUT_DIR"
    if [[ $? != 0 ]] ; then
        echo -e "$CLR_ERROR$(log_prefix) cloning failed. Aborting $CLR_RESET" >&2
        exit 1
    else:
        echo -e "$CLR_ERROR$(log_prefix) successfully cloned $REPOSITORY_URL into $CHECKOUT_DIR $CLR_RESET" >&2
    fi
fi

# Launch the 'user command' for the first time
run_user_command

while true
    do
    # check if the remote has changed
    if remote_has_changed; then
        echo -e "$CLR_OK$(log_prefix) Local branch is up to date $CLR_RESET" >&2
        sleep "$UPDATE_INTERVAL"
    else
        echo -e "$CLR_OK$(log_prefix) Remote is ahead of local branch $CLR_RESET" >&2

        # Kill the previous command (if there was one), report on the results
        terminate_user_command

        # Update the repository
        git_update

        # Restart the user command
        run_user_command
    fi
done
