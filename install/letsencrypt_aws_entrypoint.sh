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
	sed -i "s/<elb_name>/${ELB_NAME}/g" ${LETSENCRYPT_CONF_PATH}
	sed -i "s/<https_port>/${HTTPS_PORT}/g" ${LETSENCRYPT_CONF_PATH}
	sed -i "s/<domain_names>/${DOMAIN_NAMES}/g" ${LETSENCRYPT_CONF_PATH}
	sed -i "s/<key_type>/${KEY_TYPE}/g" ${LETSENCRYPT_CONF_PATH}
	sed -i "s/<private_key_path>/${PRIVATE_KEY_PATH}/g" ${LETSENCRYPT_CONF_PATH}
	sed -i "s/<acme_directory_url>/${ACME_DIRECTORY_URL}/g" ${LETSENCRYPT_CONF_PATH}
}

check_variable() {
	local VARIABLE=$1
	if [[ -z ${VARIABLE} ]]; then
		echo "ERROR! Environment variable ${!VARIABLE@} not specified. Exiting..."
		exit 1
	fi	
}



#### Orchestration

run_letsencrypt_aws() {
	echo "Running letsencrypt-aws.py with parameters; $@"
	check_aws_variables
	set_letsencrypt_aws_config
	python letsencrypt-aws.py $@
}

check_global_variables() {
	check_variable ${DOMAIN_NAMES}
}

check_aws_variables() {
	check_variable ${ELB_NAME}
	check_variable ${HTTPS_PORT}
	check_variable ${KEY_TYPE}
	check_variable ${PRIVATE_KEY_PATH}
	check_variable ${AWS_ACCESS_KEY_ID}
	check_variable ${AWS_SECRET_ACCESS_KEY}
	check_variable ${AWS_DEFAULT_REGION}
}



#### Starting point 

# Allow to run bash instead of letsencrypt
if [[ $@ == bash* ]]; then
	exec "$@"
fi

check_if_aws

if [[ $? == 0 ]]; then
	run_letsencrypt_aws
else 
	echo "Do something else..."
fi



