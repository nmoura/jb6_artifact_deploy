#!/bin/bash
#
# jb6_artifact_deploy.sh
#
# Autor: Nilton Silva de Moura <y6hw@petrobras.com.br>
#
# ----------------------------------------------------------------------------
#
# Faz cold-deploy num controlador de domínio do JBoss EAP 6.
#
# Deve ser executado em um host que tenha o JBoss EAP 6 instalado, porque
# utiliza o comando jboss-cli.sh do diretório bin/ da instalação do JBoss.
# 
# 
# ----------------------------------------------------------------------------
#

#
# Início
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
# Check if the parameters were correctly passed
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
# Get environment data from the configuration file
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
# Deploy
#
# 1. Stop servers;
# 2. Undeploy artifact;
# 3. Deploy artifact;
# 4. Start servers.
#

filename=$(basename $artifact)

$jboss_dir/bin/jboss-cli.sh --connect --controller=$domain --user=$username \
--password=$password --command="/server-group=$group:stop-servers()"

if test $? == '0' ; then
    $jboss_dir/bin/jboss-cli.sh --connect --controller=$domain \
    --user=$username --password=$password \
    --command="ls /server-group=$group/deployment" | grep ^"$filename"$ \
    &> /dev/null
else
    echo "ERROR: problem to stop the group server $group."
    exit 1
fi

if test $? == '0' ; then
    $jboss_dir/bin/jboss-cli.sh --connect --controller=$domain \
    --user=$username --password=$password \
    --command="undeploy $filename --server-groups=$group"
fi

if test $? == '0' ; then
    $jboss_dir/bin/jboss-cli.sh --connect --controller=$domain \
    --user=$username --password=$password \
    --command="deploy $artifact --server-groups=$group"
else
    echo "ERROR: problem to undeploy $filename."
    exit 1
fi

if test $? == '0' ; then
    $jboss_dir/bin/jboss-cli.sh --connect --controller=$domain \
    --user=$username --password=$password \
    --command="/server-group=$group:start-servers()"
else
    echo "ERROR: problem to deploy $filename."
    exit 1
fi

if test $? != '0' ; then
    echo "ERROR: problem to start server group $group."
    exit 1
fi
