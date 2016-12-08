# LETSENCRYPT FOR DOCKER


Developed by the Center for Virtualization and Applied Spatial Technologies (CVAST),
University of South Florida


This tool lets you download and renew certificates. It can be paired with Docker containers running web servers (e.g. Nginx).  
It also works for servers running on Amazon Web Services (AWS) behind an Elastic Load Balancer (ELB).

Additionally, it can be used to register with LetsEncrypt using your email address  
(this is done automatically when running a server not behind an AWS ELB).

Based on:  
  - letsencrypt-aws (https://github.com/alex/letsencrypt-aws)  
  - Official Certbot client (https://certbot.eff.org)  
  
Tested on:  
  - Localhost (registration only)  
  - Single AWS EC2 instance paired with an NginX container
  - AWS ECS cluster running behind an Elastic Load Balancer (also paired with an Nginx container)  
  
  
_____________________
## Usage


#### Global Environment Variables

- Required:
	- PRODUCTION_MODE: True or False. Use LetsEncrypt's staging or production server to register or get a certificate.
  
  
_____________________
#### Commands

__-h__ or __--help__ or __help__:
Display help text

__get_certificate__:	
Automatically download or renew certificate of domain(s) provided through the DOMAIN_NAMES environment variable.

  - Additional Environment Variables
    - __Both inside and outside AWS__:
        - Optional:
            - FORCE_RENEWAL: True or False. Force issue of a certificate, even if it is not due for renewal. Default = False.
            - PERSISTENT_MODE: True or False. Keep this Docker container running as a service in order to have your 
            certificates renewed automatically. Default = False.
            - ADDITIONAL_PARAMETERS: Additional parameters for either Certbot or letsencrypt-aws, other than those controlled by FORCE_RENEWAL and PERSISTENT_MODE.
            - LETSENCRYPT_RENEWAL_SLEEP_TIME: Interval between renewal checks. Default = 24 hours.

    - __Outside AWS__:
        + Required:
          - DOMAIN_NAMES: List of domain names (in a regular string).
          - LETSENCRYPT_EMAIL: Email address to be registered with LetsEncrypt.
    
        - Optional:
            - WEB_ROOT: Path used as root for ACME challange. Also point to this path in your web server configuration
                (see volume 'webserver-root' in docker-compose.yml below).
                e.g.: location ~ /.well-known/acme-challenge { allow all; root /var/www; }
                Default = /var/www
    
    - __Inside AWS__:
        + Required:
            - FORCE_NON_ELB: True of False. Set this to true when running on AWS, but not behind an ELB. 
                (We can not check this, only if it runs on an AWS EC2 instance or not.)
            - DOMAIN_NAMES: List of domain names (in a regular string).
            - ELB_NAME: Elastic Load Balancer name.
            - PRIVATE_KEY_PATH: Location of your LetsEncrypt/ACME account private key (local or AWS S3). 
                Format: 'file:///path/to/key.pem' (local file Unix), 
                'file://C:/path/to/key.pem' (local file Windows), or 
                's3://bucket-name/object-name'. 
                The key should be a PEM formatted RSA private key.
            - AWS_DEFAULT_REGION: The AWS region your services are running in.
    
        - Optional:
            - KEY_TYPE: rsa or ecdsa. Default = rsa.
            - ELB_PORT: Port used by Elastic Load Balancer. Default = 443.
            - LETSENCRYPT_BASEDIR: Base directory for LetsEncrypt files. Default = /etc/letsencrypt
            - ACME_DIRECTORY_URL_PRODUCTION: Production URL for LetsEncrypt. Default =  https://acme-v01.api.letsencrypt.org/directory
            - ACME_DIRECTORY_URL_STAGING: Staging URL for LetsEncrypt. Default = https://acme-staging.api.letsencrypt.org/directory


__register__:  
Manually registers the provided email address with LetsEncrypt/ACME.
Returns a private key in stout, or in a file if PRIVATE_KEY_PATH is provided. 

Currently this account is currently only used when running behind an AWS ELB.
In all other situations the registration is done automatically by Certbot. 
In that case the private key is saved to /etc/letsencrypt

  - Additional Environment Variables
    + Required:
        - LETSENCRYPT_EMAIL: Email address to be registered with LetsEncrypt.
        - AWS_DEFAULT_REGION: (Only if you use AWS S3 for storage) The AWS region your services are running in.

    - Optional:
        - PRIVATE_KEY_PATH: Location to save your LetsEncrypt/ACME account private key to (local or AWS S3).
            Format: 'file:///path/to/key.pem' (local file Unix), 
            'file://C:/path/to/key.pem' (local file Windows), or 
            's3://bucket-name/object-name'.



_____________________



## Volumes

When pairing cvast-letsencrypt with a web server container, a few volumes need to be created to allow communication between your containers.

##### docker-compose.yml when not behind an AWS ELB:  

	version: '2'
	services:   

	    nginx:
	      restart: always
	      image: nginx
	      ports:
	        - '80:80'
	        - '443:443'
	      volumes:
	        - nginx-root:/var/www
	        - letsencrypt-config:/etc/letsencrypt

	    letsencrypt:
	      image: cvast/cvast-letsencrypt:1.0
	      build: 
		context: .
		dockerfile: ./Dockerfile
	      command: get_certificate
	      volumes:
	        - web-root:/var/www
	        - letsencrypt-config:/etc/letsencrypt
	        - letsencrypt-log:/var/log/letsencrypt
	        - letsencrypt-workdir:/var/lib/letsencrypt
	      environment:
	        - LETSENCRYPT_EMAIL=example@mail.edu
	        - DOMAIN_NAMES=example.com www.example.com
	        - PRODUCTION_MODE=False
	        # - PRIVATE_KEY_PATH=s3://bucket-name/object-name.pem
	        - PRIVATE_KEY_PATH=file:///path/to/object-name.pem
	        - AWS_ACCESS_KEY_ID=
	        - AWS_SECRET_ACCESS_KEY=
	        - AWS_DEFAULT_REGION=
	        - FORCE_RENEWAL=False
	        - PERSISTENT_MODE=False

	  volumes:
	    web-root:
	    letsencrypt-config:
	    letsencrypt-log:
	    letsencrypt-workdir:
        
##### Configuration when behind an AWS ELB:
Same as docker-compose.yml shown above, but without the nginx-root volume (ACME challange is done on Route 53 level instead of your web server).



# AWS IAM Policy

##### AWS ELB
When running behind an ELB, certain priviledges are required. Sample IAM policy:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Allow",
            "Action": [
                "route53:ChangeResourceRecordSets",
                "route53:GetChange",
                "route53:GetChangeDetails",
                "route53:ListHostedZones"
            ],
            "Resource": [
                "*"
            ]
        },
        {
            "Sid": "",
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:DescribeLoadBalancers",
                "elasticloadbalancing:SetLoadBalancerListenerSSLCertificate"
            ],
            "Resource": [
                "*"
            ]
        },
        {
            "Sid": "",
            "Effect": "Allow",
            "Action": [
                "iam:ListServerCertificates",
                "iam:GetServerCertificate",
                "iam:UploadServerCertificate"
            ],
            "Resource": [
                "*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetBucketLocation"
            ],
            "Resource": "arn:aws:s3:::*"
        },
        {
            "Effect": "Allow",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::bucket-name/optional-folder-name/*"
            ]
        }
    ]
}
```

##### Non-AWS access
Alternatively (e.g. when not running on an AWS server, but still using an S3 bucket for storage), you can create a user policy that allows access. Be sure to specify these envrionment variables in the letsencrypt container:
  - AWS_ACCESS_KEY_ID
  - AWS_SECRET_ACCESS_KEY
  - AWS_DEFAULT_REGION


```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecs:List*",
                "ecs:Describe*",
                "ecs:UpdateService",
                "ecs:RegisterTaskDefinition",
                "application-autoscaling:Describe*",
                "application-autoscaling:PutScalingPolicy",
                "application-autoscaling:DeleteScalingPolicy",
                "application-autoscaling:RegisterScalableTarget"
            ],
            "Resource": [
                "*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject"
            ],
            "Resource": "arn:aws:s3:::cvast-config/letsencrypt/*"
        }
    ]
}
```
