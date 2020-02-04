#!/usr/bin/env bash
# ddphp.install.id 1.0.0
#
# sudo su
# bash <(curl -s https://ddphp.install.id)

# set -e

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

if [ -f /opt/elasticbeanstalk/support/envvars ]
then
	. /opt/elasticbeanstalk/support/envvars
fi

cd /tmp

if [ ! -z "${DD_AGENT_MAJOR_VERSION}" ]
then
  export DD_AGENT_MAJOR_VERSION=7
fi

if [ !-z $( which php ) ]
then
  URL=$( curl -s https://api.github.com/repos/DataDog/dd-trace-php/releases/latest | grep -E 'http.*datadog-php-tracer-.*\.x86_64\.rpm' | cut -d : -f 2,3 | cut -d '"' -f 2 )
  echo "Downloading ${URL}"
  curl -s -L -o datadog-php-tracer.rpm "${URL}"
  sudo rpm -ivh datadog-php-tracer.rpm
  rm -f datadog-php-tracer.rpm
fi

EXPORTS="export DD_TRACE_CLI_ENABLED=true
export DD_TRACE_ANALYTICS_ENABLED=true"

IP=$( curl -s ipinfo.io | grep -E '"ip":' | cut -d '"' -f 4 )
echo "External IP detected: ${IP}"

DNS=$( curl -s https://api.hackertarget.com/reverseiplookup/?q=$IP )
echo "DNS detected: ${DNS}"

if [ ! -z "${DD_API_KEY}" ]
then
	bash -c "$(curl -L https://raw.githubusercontent.com/DataDog/datadog-agent/master/cmd/agent/install_script.sh)"
fi

if [ -z "${DD_SERVICE_NAME}" ]
then
	DD_SERVICE_NAME="${APP_NAME}"
fi

if [ -z "${DD_SERVICE_NAME}" ]
then
  read -p "What is the shortest domain of this service this machine is running (eg: servicename.com)? " DD_SERVICE_NAME
fi

EXPORTS="${EXPORTS}
export DD_SERVICE_NAME=${DD_SERVICE_NAME}"
$EXPORTS
# echo -e $EXPORTS
grep -qxF "$EXPORTS" /etc/environment || sudo echo -e "${EXPORTS}" >> /etc/environment
# echo "Contents of /etc/environment:"
# cat /etc/environment

# Newrelic would compete, kill it.
rm -f /etc/php.d/newrelic.ini

# Allow env variables to go into PHP-FPM
# sudo sed -i 's/;clear_env = no/clear_env = no/g' /etc/php-fpm.d/www.conf

# Shove the variables into FPM.
if [ -f /etc/php-fpm.d/www.conf ]
then
  EXPORTSFPM="env[DD_TRACE_CLI_ENABLED] = true
env[DD_TRACE_ANALYTICS_ENABLED] = true
env[DD_SERVICE_NAME] = ${DD_SERVICE_NAME}"
  grep -qxF "EXPORTSFPM" /etc/php-fpm.d/www.conf || sudo echo -e "${EXPORTSFPM}" >> /etc/php-fpm.d/www.conf
fi

# Enable APM
sudo sed -i 's/# apm_enabled: false/apm_enabled: true/g' /etc/dd-agent/datadog.conf

# Upgrade DD agent if needed.
if [ -z "${DD_API_KEY}" ]
then
  DD_UPGRADE=true bash -c "$(curl -L https://raw.githubusercontent.com/DataDog/datadog-agent/master/cmd/agent/install_script.sh)"
fi

# Restart services.
sudo service datadog-agent restart
sudo apachectl restart
sudo service php-fpm restart
sudo service nginx restart