FROM python:2.7-slim

USER root

RUN apt-get update -y &&\
	apt-get upgrade -y &&\
	apt-get update -y &&\
	apt-get install -y build-essential &&\
	apt-get install -y libffi-dev &&\
	apt-get install -y libssl-dev &&\
	apt-get install -y git &&\
	apt-get install -y curl
	
ENV INSTALL_DIR_LOCAL=./install
ENV INSTALL_DIR=/install
ENV APP_DIR=/letsencrypt-aws
# rsa or ecdsa, optional, defaults to rsa (string)
ENV KEY_TYPE=rsa
# optional, defaults to Let's Encrypt production (string) when left empty
ENV ACME_DIRECTORY_URL=
ENV HTTPS_PORT=443
ENV LETSENCRYPT_CONF_PATH=${APP_DIR}/letsencrypt_aws.conf

WORKDIR ${INSTALL_DIR}
RUN curl -O https://bootstrap.pypa.io/get-pip.py
RUN python get-pip.py

WORKDIR ${APP_DIR}
COPY ${INSTALL_DIR_LOCAL}/requirements.txt .
RUN pip install -r ./requirements.txt
COPY ${INSTALL_DIR_LOCAL}/letsencrypt-aws.py .
COPY ${INSTALL_DIR_LOCAL}/letsencrypt_aws_entrypoint.sh .
COPY ${INSTALL_DIR_LOCAL}/letsencrypt_aws.conf .

RUN chmod 644 ./letsencrypt-aws.py
RUN chmod 777 ./letsencrypt_aws_entrypoint.sh

USER nobody

ENTRYPOINT ["/letsencrypt-aws/letsencrypt_aws_entrypoint.sh"]
CMD ["update-certificates"]