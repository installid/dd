#!/usr/bin/env bash
# ddphp.install.id 1.0.0

# Prepare error trapping.
function fdebug
{
	last_command=$current_command
	current_command=$BASH_COMMAND
}
function fexit
{
	if [ ! $? -eq 0 ]
	then
		echo -e "${RED}ERROR: Datadog PHP installation was unable to complete. \"${last_command}\" returned $?.${NC}"
	fi
	if [ -d "$tmp" ]
	then
		rm -rf "$tmp"
	fi
	if [ -f "$self" ]
	then
		shred -u "$self"
	fi
}
clear
trap fdebug DEBUG
trap fexit EXIT
self="$0"
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Check dependencies
if [ -z $( which cut ) ]
then
	echo "cut is required."
	exit 1
fi
if [ -z $( which curl ) ]
then
	echo "curl is required."
	exit 1
fi
if [ -z $( which grep ) ]
then
	echo "grep is required."
	exit 1
fi
if [ -z $( which php ) ]
then
	echo "php is required."
	exit 1
fi

if [ -f /opt/elasticbeanstalk/support/envvars ]
then
	. /opt/elasticbeanstalk/support/envvars
fi

cd /tmp

URL=$( curl -s https://api.github.com/repos/DataDog/dd-trace-php/releases/latest | grep -E 'http.*datadog-php-tracer-.*\.x86_64\.rpm' | cut -d : -f 2,3 | cut -d '"' -f 2 )
echo "Downloading ${URL}"
curl -L -o datadog-php-tracer.rpm "${URL}"

sudo rpm -ivh datadog-php-tracer.rpm
rm -f datadog-php-tracer.rpm

set -e

EXPORTS="export DD_TRACE_CLI_ENABLED=true\nexport DD_TRACE_ANALYTICS_ENABLED=true"

IP=$( curl -s ipinfo.io | grep -E '"ip":' | cut -d '"' -f 4 )
echo "External IP detected: ${IP}"

DNS=$( curl https://api.hackertarget.com/reverseiplookup/?q=$IP )
echo "DNS detected: ${DNS}"

if [ -z "${DD_SERVICE_NAME}" ]
then
	DD_SERVICE_NAME=$APP_NAME
fi

read -p "What is the shortest domain of this service this machine is running (eg: servicename.com)? [${DD_SERVICE_NAME}]: " servicename
servicename=${servicename:-$DD_SERVICE_NAME}
EXPORTS="${EXPORTS}\nexport DD_SERVICE_NAME=${servicename}"
$EXPORTS
echo $EXPORTS
grep -qxF "DD_SERVICE_NAME" /etc/environment || sudo echo "${EXPORTS}" >> /etc/environment
echo "Contents of /etc/environment:"
cat /etc/environment

sudo apachectl restart
sudo service php-fpm restart
