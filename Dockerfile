FROM python:2.7-slim

USER root

RUN echo "deb http://ftp.debian.org/debian jessie-backports main" >> /etc/apt/sources.list.d/sources.list
RUN apt-get update -y &&\
	apt-get upgrade -y &&\
	apt-get update -y &&\
	apt-get install -y build-essential &&\
	apt-get install -y libffi-dev &&\
	apt-get install -y libssl-dev &&\
	apt-get install -y git &&\
	apt-get install -y curl &&\
	apt-get install -y dos2unix &&\
	apt-get install -y certbot -t jessie-backports
	
ENV INSTALL_DIR_LOCAL=./install
ENV INSTALL_DIR=/install
ENV APP_DIR=/letsencrypt
# rsa or ecdsa, optional, defaults to rsa (string)
ENV KEY_TYPE=rsa
ENV HTTPS_PORT=443

WORKDIR ${INSTALL_DIR}
RUN curl -O https://bootstrap.pypa.io/get-pip.py
RUN python get-pip.py

COPY ${INSTALL_DIR_LOCAL}/letsencrypt_aws_requirements.txt ${INSTALL_DIR}/letsencrypt_aws_requirements.txt
RUN pip install -r ${INSTALL_DIR}/letsencrypt_aws_requirements.txt

COPY ${INSTALL_DIR_LOCAL}/letsencrypt_entrypoint.sh ${INSTALL_DIR}/letsencrypt_entrypoint.sh
COPY ${INSTALL_DIR_LOCAL}/letsencrypt-aws.py ${INSTALL_DIR}/letsencrypt-aws.py
COPY ${INSTALL_DIR_LOCAL}/letsencrypt_aws.conf ${INSTALL_DIR}/letsencrypt_aws.conf
RUN dos2unix ${INSTALL_DIR}/letsencrypt_entrypoint.sh
RUN chmod +x ${INSTALL_DIR}/letsencrypt-aws.py
RUN chmod +x ${INSTALL_DIR}/letsencrypt_entrypoint.sh


WORKDIR ${INSTALL_DIR}
ENTRYPOINT ["./letsencrypt_entrypoint.sh"]