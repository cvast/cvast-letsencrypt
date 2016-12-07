
Usage
=====


	--Global Environment Variables--

		Required:
			PRODUCTION_MODE: True or False. Use LetsEncrypt's staging or production server to register or get a certificate.



	**Commands**

	________________
	get_certificate:	

	Automatically download or renew certificate of domain(s) provided through the DOMAIN_NAMES environment variable.

		--Additional Environment Variables--
		
			--> Both inside and outside AWS:
				- Optional:
					FORCE_RENEWAL: True or False. Force issue of a certificate, even if it is not due for renewal. Default = False.
					PERSISTENT_MODE: True or False. Keep this Docker container running as a service in order to have your 
								certificates renewed automatically. Default = False.
					LETSENCRYPT_RENEWAL_SLEEP_TIME: Interval between renewal checks. Default = 24 hours.
					
			--> Outside AWS:
				+ Required:
					DOMAIN_NAMES: List of domain names (in a regular string).
					LETSENCRYPT_EMAIL: Email address to be registered with LetsEncrypt.
					
				- Optional:
					WEB_ROOT: Path used as root for ACME challange. Also point to this path in your web server configuration.
							e.g.: location ~ /.well-known/acme-challenge { allow all; root ${WEB_ROOT_DEFAULT}; }
							Default = ${WEB_ROOT_DEFAULT}

			--> Inside AWS:
				+ Required:
					FORCE_NON_ELB: True of False. Set this to true when running on AWS, but not behind an ELB. 
								(We can not check this, only if it runs on an AWS EC2 instance or not.)
					DOMAIN_NAMES: List of domain names (in a regular string).
					ELB_NAME: Elastic Load Balancer name.
					PRIVATE_KEY_PATH: Location of your LetsEncrypt/ACME account private key (local or AWS S3). 
								Format: 'file:///path/to/key.pem' (local file Unix), 
								'file://C:/path/to/key.pem' (local file Windows), or 
								's3://bucket-name/object-name'. 
								The key should be a PEM formatted RSA private key.
					AWS_DEFAULT_REGION: The AWS region your services are running in.

				- Optional:
					KEY_TYPE: rsa or ecdsa. Default = rsa.
					ELB_PORT: Port used by Elastic Load Balancer. Default = 443.
					LETSENCRYPT_BASEDIR: Base directory for LetsEncrypt files. Default = ${LETSENCRYPT_BASEDIR_DEFAULT}
					ACME_DIRECTORY_URL_PRODUCTION: Production URL for LetsEncrypt. Default = ${ACME_DIRECTORY_URL_PRODUCTION_DEFAULT}
					ACME_DIRECTORY_URL_STAGING: Staging URL for LetsEncrypt. Default = ${ACME_DIRECTORY_URL_STAGING_DEFAULT}

	_________
	register:		

	Manually registers the provided email address with LetsEncrypt/ACME.
	Returns a private key in stout, or in a file if PRIVATE_KEY_PATH is provided. 

	Currently this account is currently only used when running behind an AWS ELB.
	In all other situations the registration is done automatically by Certbot. 
	In that case the private key is saved to ${LETSENCRYPT_BASEDIR}
						
		--Additional Environment Variables--
		
			+ Required:
				LETSENCRYPT_EMAIL: Email address to be registered with LetsEncrypt.
				AWS_DEFAULT_REGION: (Only if you use AWS S3 for storage) The AWS region your services are running in.
				
			- Optional:
				PRIVATE_KEY_PATH: Location to save your LetsEncrypt/ACME account private key to (local or AWS S3).
							Format: 'file:///path/to/key.pem' (local file Unix), 
							'file://C:/path/to/key.pem' (local file Windows), or 
							's3://bucket-name/object-name'.
			
	-h or --help or help: Display help text



Volumes
=======

When pairing cvast-letsencrypt with a web server container, a few volumes need to be created to allow communication between your containers.

docker-compose.yml when not behind an AWS ELB:
    nginx:
      image: your-webserver-image/your-repository:build-number
      ports:
        - '80:80'
        - '443:443'
      volumes:
        - nginx-root:/var/www
        - letsencrypt-config:/etc/letsencrypt
    
    letsencrypt:
      image: cvast/cvast-letsencrypt:1
      volumes:
        - nginx-root:/var/www
        - letsencrypt-config:/etc/letsencrypt
      command: get_certificate
      environment:
        - FORCE_NON_ELB=True
        - LETSENCRYPT_EMAIL=your-email@example.com
        - DOMAIN_NAMES=example.com www.example.com
        - PRODUCTION_MODE=False
        
    volumes:
        nginx-root:
        letsencrypt-config:
        
docker-compose.yml (or other configuration, e.g. ECS) when behind an AWS ELB:
    Same as docker-compose.yml shown above, but without the nginx-root volume (ACME challange is done on Route 53 level instead of your web server).