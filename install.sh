#!/usr/bin/env bash
# dd.install.id 1.0.0
#
# Install Datadog standard agent and APM for whatever platform you are on.
#
# Install:
#   DD_API_KEY=xxxxxxx bash <(wget -qO- dd.install.id)
#   -or-
#   DD_SERVICE_NAME=servicename.com DD_API_KEY=xxxxxxx bash <(wget -qO- dd.install.id)
#   -or-
#   DD_PLATFORM=java DD_SERVICE_NAME=servicename.com DD_API_KEY=xxxxxxx bash <(wget -qO- dd.install.id)
#
# Upgrade only:
#   bash <(wget -qO- dd.install.id)

# set -e

# Prepare error trapping.
function fdebug
{
	last_command=$current_command
	current_command=$BASH_COMMAND
}
function ferr
{
  echo -e "${RED}$1${NC}" && exit 1
}
function fexit
{
	if [ ! $? -eq 0 ]
	then
		echo -e "${RED}ERROR: Datadog installation was unable to complete. \"${last_command}\" returned $?.${NC}"
	fi
  #	if [ -d "$tmp" ]
  #	then
  #		rm -rf "$tmp"
  #	fi
	if [ -f "$self" ]
	then
		shred -u "$self"
	fi
	cd -
}
clear
trap fdebug DEBUG
trap fexit EXIT
self="$0"
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Check dependencies
if [ -z $( which cut 2>/dev/null ) ]
then
	ferr "cut is required."
fi
if [ -z $( which curl 2>/dev/null ) ]
then
	echo "curl is required."
fi
if [ -z $( which grep 2>/dev/null ) ]
then
	echo "grep is required."
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

if [ -z "${DD_PLATFORM}" ]
then
  DD_PLATFORM=php
  export DD_PLATFORM=php
fi

if [ ! -z $( which ${DD_PLATFORM} 2>/dev/null ) ]
then
  URL=$( curl -s "https://api.github.com/repos/DataDog/dd-trace-${DD_PLATFORM}/releases/latest" | grep -E "http.*datadog-${DD_PLATFORM}-tracer-.*\.x86_64\.rpm" | cut -d : -f 2,3 | cut -d '"' -f 2 )
  echo "Downloading ${URL} --> datadog-${DD_PLATFORM}-tracer.rpm"
  curl -s -L -o datadog-${DD_PLATFORM}-tracer.rpm "${URL}"
  if [ -f "datadog-${DD_PLATFORM}-tracer.rpm" ]
  then
    sudo rpm -ivh datadog-${DD_PLATFORM}-tracer.rpm
    rm -f datadog-${DD_PLATFORM}-tracer.rpm
  else
    ferr "Could not download APM agent as datadog-${DD_PLATFORM}-tracer.rpm for this platform."
  fi
fi

EXPORTS="export DD_TRACE_CLI_ENABLED=true
export DD_TRACE_ANALYTICS_ENABLED=true"

IP=$( curl -s ipinfo.io | grep -E '"ip":' | cut -d '"' -f 4 )
echo "External IP detected: ${IP}"

DNS=$( curl -s "https://api.hackertarget.com/reverseiplookup/?q=${IP}" )
echo "DNS detected: ${DNS}"

if [ ! -z "${DD_API_KEY}" ]
then
	DD_AGENT_MAJOR_VERSION=7 bash -c "$(curl -L https://raw.githubusercontent.com/DataDog/datadog-agent/master/cmd/agent/install_script.sh)"
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

# Enable APM
sudo sed -i 's/# apm_enabled: false/apm_enabled: true/g' /etc/dd-agent/datadog.conf

# Upgrade DD agent if needed.
if [ -z "${DD_API_KEY}" ]
then
  DD_AGENT_MAJOR_VERSION=7 DD_UPGRADE=true bash -c "$(curl -L https://raw.githubusercontent.com/DataDog/datadog-agent/master/cmd/agent/install_script.sh)"
fi

if [ "php" == "${DD_PLATFORM}" ]
then
  # PHP specific platform changes.
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
    grep -qxF "$EXPORTSFPM" /etc/php-fpm.d/www.conf || sudo echo -e "${EXPORTSFPM}" >> /etc/php-fpm.d/www.conf
    sudo service php-fpm restart
  fi

  YAML="logs:"
  for FOLDER in $( find /var -type d -name logs 2>/dev/null | grep storage/logs )
  do
    YAML="${YAML}

  - type: file
    path: '${FOLDER}/*'
    service: php
    source: php
    sourcecategory: sourcecode
"
  done
  grep -qxF "$YAML" /etc/php.d/conf.yaml || sudo echo -e "${EXPORTSFPM}" >> /etc/php.d/conf.yaml
fi
# Restart services.
# sudo service datadog-agent restart
sudo restart datadog-agent
if [ ! -z $( which apachectl 2>/dev/null ) ]
then
	sudo apachectl restart
fi
sudo service nginx restart