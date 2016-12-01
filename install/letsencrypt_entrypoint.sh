#!/bin/bash

set -e 

#### Global variables
NGINX_ROOT=/var/www

set -- ${DOMAIN_NAMES}
PRIMARY_DOMAIN_NAME=$1
LETSENCRYPT_BASEDIR="${LETSENCRYPT_BASEDIR:-/etc/letsencrypt}"
LETSENCRYPT_LIVEDIR=${LETSENCRYPT_BASEDIR}/live
LETSENCRYPT_DOMAIN_DIR=${LETSENCRYPT_LIVEDIR}/${PRIMARY_DOMAIN_NAME}
LETSENCRYPT_CERTIFICATE_PATH=${LETSENCRYPT_DOMAIN_DIR}/fullchain.pem
LETSENCRYPT_PRIVATE_KEY_PATH=${LETSENCRYPT_DOMAIN_DIR}/privkey.pem
LETSENCRYPT_AWS_PARAMETERS=update-certificates --persistent
# For Letsencrypt / Certbot verification
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}
LETSENCRYPT_RENEWAL_SLEEP_TIME="${LETSENCRYPT_RENEWAL_SLEEP_TIME:-12h}"

#### Basic functions

# Default LetsEncrypt functions
download_certificates() {
	echo "Preparing to download new certificate from LetsEncrypt..."
	mkdir -p ${NGINX_ROOT}/${PRIMARY_DOMAIN_NAME}
	set_folder_permissions	
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
		${ADDITIONAL_CERTBOT_PARAMS}
	
	local exit_code=$?
	if [[ ${exit_code} != 0 ]]; then
		echo "Failed to download certificate with Certbot. Exit code: ${exit_code}. Exiting..."
		exit ${exit_code}
	fi
	
	set -e
}

renew_certificates() {
	echo "Checking if certificates needs to be renewed..."
	certbot renew
}

persist_renewal_certificates() {
	while true; do
		renew_certificates
		echo "Next renew attempt will be in: ${LETSENCRYPT_RENEWAL_SLEEP_TIME}"
		sleep ${LETSENCRYPT_RENEWAL_SLEEP_TIME}
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
	# If we can get an AWS private ip, it means we are on an EC2 instance
	AWS_PRIVATE_IP=`curl -s http://169.254.169.254/latest/meta-data/local-ipv4`
	if [[ ! -z $AWS_PRIVATE_IP ]]; then
		echo "Running on AWS EC2 instance..."
		return 0
	else
		echo "Not running on AWS EC2 instance..."
		return 1
	fi
}

set_letsencrypt_aws_config() {
	echo "Applying settings provided through environment variables..."
	read -d '' LETSENCRYPT_AWS_CONFIG <<- EOF
	{
		"domains": [
			{
				"elb": {
					"name": "${ELB_NAME}"
				},
				"hosts": ["${DOMAIN_NAMES}"],
				"key_type": "${KEY_TYPE}"
			}
		],
		"acme_account_key": "${PRIVATE_KEY_PATH}",
		"target_certificate_path": "<target_certificate_dir>"
	}
EOF

	export LETSENCRYPT_AWS_CONFIG
}

download_certificates_letsencrypt_aws() {
	echo "Running letsencrypt-aws.py to download certificates with parameters: ${LETSENCRYPT_AWS_PARAMETERS}"
	python letsencrypt-aws.py ${LETSENCRYPT_AWS_PARAMETERS}
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



#### Orchestration

main_orchestration() {
	if [[ ${DOMAIN_NAMES} == "localhost" ]]; then
		echo "Running on localhost, so not downloading certificates. Exiting..."
		exit 0
	else
		if [[ ${FORCE_NON_AWS} == True ]]; then
			run_letsencrypt
		else
			set +e
			check_if_aws
			local exit_code=$?
			set -e
			if [[ ${exit_code} == 1 ]]; then
				run_letsencrypt
				echo "Letsencrypt has done its job, exiting..."
				exit 0
			elif  [[ ${exit_code} == 0 ]]; then
				run_letsencrypt_aws
				echo "Letsencrypt has done its job, exiting..."
				exit 0
			else
				
				echo "Something went wrong at 'check_if_aws'. Exit code: ${exit_code}. Exiting..."
				exit ${exit_code}
			fi	
		fi
	fi	
}

run_letsencrypt_aws() {
	echo "+++ Executing LetsEncrypt for AWS EC2 instances running behind an Elastic Loadbalancer +++"
	check_aws_variables
	set_letsencrypt_aws_config
	download_certificates_letsencrypt_aws
}

run_letsencrypt() {
	echo "+++ Executing LetsEncrypt in standard mode +++"
	set +e
	check_certificate_exists
	local exit_code=$?
	set -e
	if [[ ${exit_code} == 0 ]]; then
		renew_certificates
	elif  [[ ${exit_code} == 1 ]]; then
		download_certificates
	else
		echo "Something went wrong at 'check_certificate_exists'. Exit code: ${exit_code}. Exiting..."
		exit ${exit_code}
	fi
	
	persist_renewal_certificates
}

check_global_variables() {
	echo "Checking global environment variables..."
	check_variable "${DOMAIN_NAMES}" DOMAIN_NAMES
	echo "All global environment variables provided"
}

check_letsencrypt_variables() {
	echo "Checking letsencrypt environment variables..."
	check_variable "${NGINX_CONTAINER}" NGINX_CONTAINER
	check_variable "${LETSENCRYPT_EMAIL}" LETSENCRYPT_EMAIL
	echo "All letsencrypt environment variables provided"
}

check_aws_variables() {
	echo "Checking aws-specific environment variables..."
	check_variable ${ELB_NAME} ELB_NAME
	check_variable ${KEY_TYPE} KEY_TYPE
	check_variable ${ACME_DIRECTORY_URL} ACME_DIRECTORY_URL
	check_variable ${PRIVATE_KEY_PATH} PRIVATE_KEY_PATH
	check_variable ${AWS_ACCESS_KEY_ID} AWS_ACCESS_KEY_ID
	check_variable ${AWS_SECRET_ACCESS_KEY} AWS_SECRET_ACCESS_KEY
	check_variable ${AWS_DEFAULT_REGION} AWS_DEFAULT_REGION
	echo "All aws-specific environment variables provided"
}



#### Starting point 

# Allow to run bash instead of letsencrypt
if [[ $@ == bash* ]]; then
	exec "$@"
else
	ADDITIONAL_PARAMETERS=$@
fi

check_global_variables
display_domain_names
main_orchestration
