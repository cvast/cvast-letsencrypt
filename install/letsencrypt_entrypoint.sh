#!/bin/bash

COMPLETE_USER_INPUT=$@
COMMAND=$1
OPTIONS="${@:2}"

set -e 




#### Global variables
NGINX_ROOT=/var/www
RUNNING_ON_AWS=False

# Get the first domain in the list
set -- ${DOMAIN_NAMES}
PRIMARY_DOMAIN_NAME=$1
LETSENCRYPT_BASEDIR="${LETSENCRYPT_BASEDIR:-/etc/letsencrypt}"
LETSENCRYPT_LIVEDIR=${LETSENCRYPT_BASEDIR}/live
LETSENCRYPT_DOMAIN_DIR=${LETSENCRYPT_LIVEDIR}/${PRIMARY_DOMAIN_NAME}
LETSENCRYPT_CERTIFICATE_PATH=${LETSENCRYPT_DOMAIN_DIR}/fullchain.pem
LETSENCRYPT_PRIVATE_KEY_PATH=${LETSENCRYPT_DOMAIN_DIR}/privkey.pem
# For Letsencrypt / Certbot verification
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}
LETSENCRYPT_RENEWAL_SLEEP_TIME="${LETSENCRYPT_RENEWAL_SLEEP_TIME:-24h}"
ACME_DIRECTORY_URL_PRODUCTION="${ACME_DIRECTORY_URL_PRODUCTION:-https://acme-v01.api.letsencrypt.org/directory}"
ACME_DIRECTORY_URL_STAGING="${ACME_DIRECTORY_URL_STAGING:-https://acme-staging.api.letsencrypt.org/directory}"
ACME_DIRECTORY_URL=${ACME_DIRECTORY_URL_STAGING}
KEY_TYPE="${KEY_TYPE}:-rsa"
FORCE_RENEWAL="${FORCE_RENEWAL:-False}"
FORCE_RENEWAL_CERTBOT="--force-renewal"
FORCE_RENEWAL_AWS="--force-issue"
PERSISTENT_MODE="${PERSISTENT_MODE:-False}"
PERSISTENT_MODE_AWS="--persistent}"
ADDITIONAL_PARAMETERS=""
RUNNING_MODE=""

HELP_TEXT="

______________________
LETSENCRYPT FOR DOCKER

Developed by the Center for Virtualization and Applied Spatial Technologies (CVAST), 
University of South Florida


This tool can download and renew certificates, including for servers running on Amazon Web Services (AWS) behind an Elastic Load Balancer(ELB).
It can also be used to register with LetsEncrypt using your email address (this is done automatically when running a server not behind an AWS ELB). 

______
Usage:


--Global Environment Variables--

	Required:
		PRODUCTION_MODE: True or False. Use LetsEncrypt's staging or production server to register or get a certificate.



**Commands**

________________
get_certificate:	

Automatically download or renew certificate of domain(s) provided through the DOMAIN_NAMES environment variable.
						
		--Environment Variables--
		
			--> Both inside and outside AWS:
				- Optional:
					FORCE_RENEWAL: True or False. Force issue of a certificate, even if it is not due for renewal. Default = False.
					PERSISTENT_MODE: True or False. Keep this Docker container running as a service in order to have your 
								certificates renewed automatically. Default = False.
					LETSENCRYPT_RENEWAL_SLEEP_TIME: Interval between renewal checks. Defaults to 24 hours.
					
			--> Outside AWS:
				+ Required:
					DOMAIN_NAMES: List of domain names (in a regular string).
					LETSENCRYPT_EMAIL: Email address to be registered with LetsEncrypt.
					
				- Optional:

			--> Inside AWS:
				+ Required:
					FORCE_NON_ELB: True of False. Set this to true when running on AWS, but not behind an ELB. 
								(We can not check this, only if it runs on an AWS EC2 instance or not.)
					DOMAIN_NAMES: List of domain names (in a regular string).
					ELB_NAME: Elastic Load Balancer name.
					PRIVATE_KEY_PATH: Location of your account private key (local or AWS S3).

				- Optional:
					KEY_TYPE: rsa or ecdsa. Defaults to rsa (string)	
					LETSENCRYPT_BASEDIR: Base directory for LetsEncrypt files. Defaults to /etc/letsencrypt
					ACME_DIRECTORY_URL_PRODUCTION: Production URL for LetsEncrypt. Defaults to https://acme-v01.api.letsencrypt.org/directory}
					ACME_DIRECTORY_URL_STAGING: Staging URL for LetsEncrypt. Defaults to https://acme-staging.api.letsencrypt.org/directory}

_____________
register_aws:		

Register the email address provided through the LETSENCRYPT_EMAIL environment variable with LetsEncrypt when running on AWS servers.
						
		--Environment Variables--
		
			+ Required:
				LETSENCRYPT_EMAIL: Email address to be registered with LetsEncrypt.

			
-h or --help or help: Display help text




"


#### Basic functions

# Default LetsEncrypt functions
download_certificates() {
	echo "Preparing to download new certificate from LetsEncrypt..."
	mkdir -p ${NGINX_ROOT}/${PRIMARY_DOMAIN_NAME}
	LETSENCRYPT_DOMAIN_PARAMETERS="$(create_domain_name_parameters)"

		
	set +e
	
	echo "Starting Certbot to download certificate"
	certbot certonly \
		--agree-tos \
		--text \
		--non-interactive \
		--email ${LETSENCRYPT_EMAIL} \
		--webroot \
		-w ${NGINX_ROOT} \
		${LETSENCRYPT_DOMAIN_PARAMETERS} \
		${RUNNING_MODE} \
		${ADDITIONAL_PARAMETERS}
	
	local exit_code=$?
	if [[ ${exit_code} != 0 ]]; then
		echo "Failed to download certificate with Certbot. Exit code: ${exit_code}. Exiting..."
		exit ${exit_code}
	fi
	
	set -e
}

renew_certificates() {
	echo "Checking if certificates needs to be renewed..."
	certbot renew ${RUNNING_MODE} ${ADDITIONAL_PARAMETERS}
}

persist_renewal_certificates() {
	while true; do
		renew_certificates
		echo "Next renew attempt will be in: ${LETSENCRYPT_RENEWAL_SLEEP_TIME}"
		sleep_for_renewal
	done
}

create_domain_name_parameters() {
	letsencrypt_domain_parameters=""
	domain_name_array=(${DOMAIN_NAMES})
	for domain_name in ${domain_name_array}; do
		letsencrypt_domain_parameters+=" -d ${domain_name}"
	done
	echo ${letsencrypt_domain_parameters}
}


# AWS-specific LetsEncrypt functions
check_if_aws() {
	set +e
	# If we can get an AWS private ip, it means we are on an EC2 instance
	AWS_PRIVATE_IP=`curl -s http://169.254.169.254/latest/meta-data/local-ipv4`
	local exit_code=$?
	set -e
	
	if [[ $exit_code == 0 ]] && [[ ! -z ${AWS_PRIVATE_IP} ]]; then
		echo "Running on AWS EC2 instance..."
		RUNNING_ON_AWS=True
	elif [[ $exit_code == 7 ]] || [[ -z ${AWS_PRIVATE_IP} ]]; then
		echo "Not running on AWS EC2 instance..."
		RUNNING_ON_AWS=False
	else
		echo "Something went wrong at 'check_if_aws'. Exit code: ${exit_code}. Exiting..."
		exit ${exit_code}	
	fi
}

set_letsencrypt_aws_config() {
	echo "Applying settings provided through environment variables..."
	LETSENCRYPT_AWS_CONFIG="
	{
		\"domains\": [
			{
				\"elb\": {
					\"name\": \"${ELB_NAME}\"
				},
				\"hosts\": [\"${DOMAIN_NAMES}\"],
				\"key_type\": \"${KEY_TYPE}\"
			}
		],
		\"acme_account_key\": \"${PRIVATE_KEY_PATH}\",
		\"acme_directory_url\": \"${ACME_DIRECTORY_URL}\",
		\"target_certificate_dir\": \"${LETSENCRYPT_LIVEDIR}\"
	}
"
	
	export LETSENCRYPT_AWS_CONFIG
}

download_certificates_letsencrypt_aws() {
	echo "Running letsencrypt-aws.py to download certificates with command: update-certificates ${ADDITIONAL_PARAMETERS}"
	python letsencrypt-aws.py update-certificates ${ADDITIONAL_PARAMETERS}
}

register_emailaddress() {
	local emailaddress=$@
	echo "Running letsencrypt-aws.py to register email address: ${emailaddress}"
	python letsencrypt-aws.py register ${emailaddress}
}

display_domain_names() {
	echo "Provided domain names: ${DOMAIN_NAMES}"
	echo "Primary domain name: ${PRIMARY_DOMAIN_NAME}"
}

# Misc
check_variable() {
	local VARIABLE_VALUE=$1
	local VARIABLE_NAME=$2
	if [[ -z ${VARIABLE_VALUE} ]] || [[ "${VARIABLE_VALUE}" == "" ]]; then
		echo "ERROR! Environment variable ${VARIABLE_NAME} not specified. Exiting..."
		exit 1
	fi	
}

check_certificate_exists() {
	if [[ -f "${LETSENCRYPT_CERTIFICATE_PATH}" ]]; then
		echo "Certificate already exists in ${LETSENCRYPT_DOMAIN_DIR}"
		return 0
	else
		echo "No certificate exists in ${LETSENCRYPT_DOMAIN_DIR}"
		return 1
	fi
}

sleep_for_renewal() {
	sleep ${LETSENCRYPT_RENEWAL_SLEEP_TIME}
}

set_running_mode() {
	if [[ "${PRODUCTION_MODE}" == True ]]; then
		ACME_DIRECTORY_URL=${ACME_DIRECTORY_URL_PRODUCTION}
	elif [[ "${PRODUCTION_MODE}" == False  ]]; then
		RUNNING_MODE="--staging"
		ACME_DIRECTORY_URL=${ACME_DIRECTORY_URL_STAGING}
	else
		echo "Options for required environment variable PRODUCTION_MODE: True | False"
		echo "Exiting..."
		display_help
		exit 1
	fi
}

set_additional_parameters() {
	if [[ "${PERSISTENT_MODE}" == True ]] && [[ "${FORCE_RENEWAL}" == True ]]; then
		echo "Error: Environment variables PERSISTENT_MODE and FORCE_RENEWAL cannot both be true, exiting..."
		exit 1
	fi		
	
	if [[ ${RUNNING_ON_AWS} == True ]]; then
		if [[ "${PERSISTENT_MODE}" == True ]]; then		
			ADDITIONAL_PARAMETERS=${PERSISTENT_MODE_AWS}
		fi
		
		if [[ "${FORCE_RENEWAL}" == True ]]; then
			ADDITIONAL_PARAMETERS=${FORCE_RENEWAL_AWS}
		fi
	else
		if [[ "${FORCE_RENEWAL}" == True ]]; then
			ADDITIONAL_PARAMETERS=${FORCE_RENEWAL_CERTBOT}
		fi	
	fi
}

display_help() {
	echo "${HELP_TEXT}"
}




#### Orchestration

run_letsencrypt_aws() {
	echo "+++ Executing LetsEncrypt for AWS EC2 instances running behind an Elastic Loadbalancer +++"
	check_aws_variables
	set_letsencrypt_aws_config
	download_certificates_letsencrypt_aws
}

run_letsencrypt_standard() {
	echo "+++ Executing LetsEncrypt in standard mode +++"
	set +e
	check_certificate_exists
	local exit_code=$?
	set -e
	
	if [[ ${exit_code} == 0 ]]; then
		renew_certificates
	else
		download_certificates
	fi
	
	if [[ "${PERSISTENT_MODE}" == True ]]; then
		sleep_for_renewal
		persist_renewal_certificates
	fi
}

check_global_variables() {
	echo "Checking global environment variables..."
	check_variable "${PRODUCTION_MODE}" PRODUCTION_MODE
	echo "All global environment variables provided"
}

check_letsencrypt_variables() {
	echo "Checking letsencrypt environment variables..."
	check_variable "${DOMAIN_NAMES}" DOMAIN_NAMES
	check_variable "${LETSENCRYPT_EMAIL}" LETSENCRYPT_EMAIL
	echo "All letsencrypt environment variables provided"
}

check_aws_variables() {
	echo "Checking aws-specific environment variables..."
	check_variable "${DOMAIN_NAMES}" DOMAIN_NAMES
	check_variable ${ELB_NAME} ELB_NAME
	check_variable ${PRIVATE_KEY_PATH} PRIVATE_KEY_PATH
	check_variable ${FORCE_NON_ELB} FORCE_NON_ELB
	echo "All aws-specific environment variables provided"
}

check_register_aws_variables() {
	echo "Checking aws-specific environment variables for registering email address..."
	check_variable ${LETSENCRYPT_EMAIL} LETSENCRYPT_EMAIL
	echo "All aws-register-specific environment variables provided"
}




#### Commands 

get_certificate() {	
	if [[ "${DOMAIN_NAMES}" == "localhost" ]]; then
		echo "Running on localhost, so not downloading certificates. Exiting..."
		exit 0
	else
		check_global_variables
		set_running_mode
		set_additional_parameters
		display_domain_names
		if [[ ${FORCE_NON_ELB} == True ]]; then
			run_letsencrypt_standard ${ADDITIONAL_PARAMETERS}
		else
			check_if_aws
			if [[ ${RUNNING_ON_AWS} == True ]]; then
				run_letsencrypt_aws ${ADDITIONAL_PARAMETERS}
			else
				run_letsencrypt_standard ${ADDITIONAL_PARAMETERS}
			fi	
		fi
		
		echo "Letsencrypt has done its job, exiting..."
		exit 0
	fi	
}

register_aws() {
	set_running_mode
	check_if_aws
	if [[ ${RUNNING_ON_AWS} == False ]]; then
		echo "Running an AWS command on a non-AWS environment, exiting..."
		exit 1
	else  
		check_register_aws_variables
		set_letsencrypt_aws_config
		register_emailaddress
		echo "Letsencrypt has done its job, exiting..."
		exit 0
	fi
}




#### Starting point 

if [[ -z ${COMPLETE_USER_INPUT} ]]; then
	echo "No command provided, exiting..."
	display_help
	exit 0
fi


if [[ ${COMMAND} == get_certificate ]]; then
	get_certificate ${OPTIONS}
elif [[ ${COMMAND} == register ]]; then
	register_aws ${OPTIONS}
elif [[ ${COMMAND} == -h ]] || [[ ${COMMAND} == --help ]] || [[ ${COMMAND} == help ]]; then
	display_help
	exit 0
else
	exec "${COMPLETE_USER_INPUT}"
fi

