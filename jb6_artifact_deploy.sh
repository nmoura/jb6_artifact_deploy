#!/bin/bash
#
# jb6_artifact_deploy.sh
#
# Nilton Moura <github.com/nmoura>
#
# ----------------------------------------------------------------------------
#
# Do stop-undeploy-deploy-start in a JBoss EAP 6 domain
#
# The jb6_artifact_deploy.conf must have at least the jboss_dir variable
# configured, with a JBoss 6 EAP directory that contains ./bin/jboss-cli.sh.
#
# Example: jboss_dir = /opt/jboss/jboss-eap-6.2
#
# 
# ----------------------------------------------------------------------------
#

usage_message="
Usage: $(basename "$0") -a file -g group [-c configuration file] \\
{-e environment | -d domain -u username -s password} [-p port]

  -c    Configuration file (optional,  default jb6_artifact_deploy.conf)
  -e    Environment (the section in the configuration file)
  -a    The artifact file to be deployed
  -g    The group name in the domain to deploy
  -d    The domain hostname where to deploy
  -p    The domain port (optional - default 9999 assumed)
  -u    The username to login in the domain
  -s    The password of the username to login in the domain
  -h    Shows this help message and exit

The -e and the -d/-u/-s options are mutually exclusive.

Examples:

$ "$0" -e dsv -a test.war -g test-group

(The above example assumes that you have the [dsv] section in the
configuration file)

$ "$0" -d hostname.domain.com -u adminuser -s adminpassword -a test.war \\
-g test-group
"

if test -z "$1" ; then
    echo "$usage_message"
    exit 0
fi

while test -n "$1" ; do
    case "$1" in
	-h)
	    echo "$usage_message"
	    exit 0
	;;

	-c)
	    conffile="$2"
	;;

	-e)
	    environment="$2"
	;;

	-a)
	    artifact="$2"
	;;

	-g)
	    group="$2"
	;;

	-d)
	    domain="$2"
	;;

	-p)
	    port="$2"
	;;

	-u)
	    username="$2"
	;;

	-s)
	    password="$2"
	;;

	*)
	    # invalid option.
	;;
    esac
    shift
done

#
# parse_conf() function
#
# Parser for the configuration file.
#
parse_conf(){
  echo $(sed -e '/./{H;$!d;}' -e 'x;/\['$1'\]/b' -e d "$conffile" \
| grep ^"$2 "= | cut -d '=' -f 2)
}

#
# Check if the parameters were correctly passed.
#
if test -z "$conffile" ; then
  conffile="$(dirname $0)/jb6_artifact_deploy.conf"
fi

if test -z "$environment" ; then
  if [ -z "$domain" ] || [ -z "$username" ] || [ -z "$password" ] ; then
    echo -n "ERROR: inform the environment or domain/username/password. "
    echo "Run \"$0 -h\" to help."
    exit 1
  fi
fi

if [ -z "$group" ] || [ -z "$artifact" ] ; then
  echo -n "ERROR: artifact and group must be informed. "
  echo "Run \"$0 -h\" to help."
  exit 1
fi

if test -z "$port" ; then
  port=9999
fi

#
# Get environment data from the configuration file.
#
if test -n "$environment" ; then
  if test -z $domain ; then
    domain=$(parse_conf $environment domain)
  fi
  if test -z $port ; then
    port=$(parse_conf $environment port)
  fi
  if test -z $username ; then
    username=$(parse_conf $environment username)
  fi
  if test -z $password ; then
    password=$(parse_conf $environment password)
  fi
fi

if [ -z "$domain" ] || [ -z "$group" ] || [ -z "$username" ] \
|| [ -z "$password" ] ; then
  echo -n "ERROR: put the domain/username/password in the $environment "
  echo -n "section, in the $(basename $conffile) configuration file. "
  echo "Run \"$0 -h\" to help."
  exit 1
fi

jboss_dir=$(parse_conf global jboss_dir)

if [ ! -d $jboss_dir ] || [ ! -x $jboss_dir/bin/jboss-cli.sh ]; then
  echo -n "ERROR: put the JBoss directory in the jboss_dir variable, in "
  echo "the [global] section in the $conffile."
  exit 1
fi

#
# This section creates a variable called server_in_hc which is a list of
# host_controller/server_instance entries, to treat them individually,
# because stop-group and start-group commands doesn't have blocking attribute.
# So, there's not a way to assure success or not, unless using stop and start
# commands for each server instance individually.
#
hcs=$($jboss_dir/bin/jboss-cli.sh --connect --controller=$domain \
--user=$username --password=$password --command="ls /host=")

for hc in $hcs ; do

  hc_srvconf=$($jboss_dir/bin/jboss-cli.sh --connect --controller=$domain \
  --user=$username --password=$password --command="ls /host=$hc/server-config")

  for server in $hc_srvconf ; do
    hc_srvgroup=$($jboss_dir/bin/jboss-cli.sh --connect --controller=$domain \
    --user=$username --password=$password \
    --command="/host=$hc/server-config=$server:read-attribute(name=group)" \
    | grep $group)

    if [ $? == "0" ] ; then
      server_in_hc="$server_in_hc $hc/$server"
    fi

  done

done

#
# Stop each server individually.
#
for entry in $server_in_hc ; do

  hc=$(echo $entry | cut -d '/' -f 1)
  server=$(echo $entry | cut -d '/' -f 2)

  echo "Stopping $server on $hc."
  stopcmd=$($jboss_dir/bin/jboss-cli.sh --connect --controller=$domain \
  --user=$username --password=$password \
  --command="/host=$hc/server-config=$server:stop(blocking=true)")

  stopresult=$(echo $stopcmd | cut -d ',' -f 1 | cut -d '>' -f 2 | tr -d ' ')
  if [ "$stopresult" != '"success"' ] ; then
    echo "ERROR: Unsuccessful stop command for $server from $hc."
    exit 1
  fi

done

#
# Check if the server group has the $filename deployed. If true, do the
# undeploy on the server group.
#
filename=$(basename $artifact)

$jboss_dir/bin/jboss-cli.sh --connect --controller=$domain \
--user=$username --password=$password \
--command="ls /server-group=$group/deployment" | grep ^"$filename"$ \
&> /dev/null

if test $? == '0' ; then

    echo "Undeploying $filename from $group server group."
    $jboss_dir/bin/jboss-cli.sh --connect --controller=$domain \
    --user=$username --password=$password \
    --command="undeploy $filename --server-groups=$group"
#    &> /dev/null

    if test $? != '0' ; then
      echo "ERROR: problem to undeploy $filename on $group server group."
      exit 1
    fi

fi

#
# Deploy the $filename on the server group.
#
echo "Deploying $filename on $group server group."
$jboss_dir/bin/jboss-cli.sh --connect --controller=$domain \
--user=$username --password=$password \
--command="deploy $artifact --server-groups=$group"

if test $? != '0' ; then
  echo "ERROR: problem to deploy $filename on $group server group."
  exit 1
fi

#
# Start each server individually.
#
for entry in $server_in_hc ; do

  hc=$(echo $entry | cut -d '/' -f 1)
  server=$(echo $entry | cut -d '/' -f 2)

  echo "Starting $server on $hc."
  startcmd=$($jboss_dir/bin/jboss-cli.sh --connect --controller=$domain \
  --user=$username --password=$password \
  --command="/host=$hc/server-config=$server:start(blocking=true)")

  startresult=$(echo $startcmd | cut -d ',' -f 1 | cut -d '>' -f 2 | tr -d ' ')
  if [ "$startresult" != '"success"' ] ; then
    echo "ERROR: Unsuccessful start command for $server on $hc."
    exit 1
  fi

done
