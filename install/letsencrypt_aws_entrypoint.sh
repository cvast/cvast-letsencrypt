#!/bin/bash


#### Basic functions

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
		"acme_account_key": "${PRIVATE_KEY_PATH}"
	}
EOF

	export LETSENCRYPT_AWS_CONFIG
}

check_variable() {
	local VARIABLE_VALUE=$1
	local VARIABLE_NAME=$2
	if [[ -z ${VARIABLE_VALUE} ]] || [[ "${VARIABLE_VALUE}" == "" ]]; then
		echo "ERROR! Environment variable ${VARIABLE_NAME} not specified. Exiting..."
		exit 1
	fi	
}



#### Orchestration

run_letsencrypt_aws() {
	check_aws_variables
	set_letsencrypt_aws_config
	
	echo "Running letsencrypt-aws.py with parameters: ${LETSENCRYPT_PARAMETERS}"
	python letsencrypt-aws.py ${LETSENCRYPT_PARAMETERS}
}

check_global_variables() {
	echo "Checking global environment variables..."
	check_variable "${DOMAIN_NAMES}" DOMAIN_NAMES
	echo "All global environment variables provided"
}

check_aws_variables() {
	echo "Checking aws-specific environment variables..."
	check_variable ${ELB_NAME} ELB_NAME
	check_variable ${HTTPS_PORT} HTTPS_PORT
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
	LETSENCRYPT_PARAMETERS=$@
fi

check_global_variables

check_if_aws

if [[ $? == 0 ]]; then
	run_letsencrypt_aws
else 
	echo "Do something else..."
fi



