FROM alpine:3.11.6

WORKDIR /app

# Prep base system
RUN set -e \
	&& ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime \
	&& apk --update add --no-cache --virtual .build-deps \
	&& apk add --no-cache \
		build-base \
		python3-dev \
		libffi-dev \
		openssl-dev \
		git \
		py3-pip \
		jq \
		curl \
		libffi \
		openssl \
	&& pip3 install --upgrade \
		awscli==1.18.49 \
		s3cmd==2.1.0 \
		credstash==1.17.1 \
	&& apk --purge -v del \
		build-base \
		py3-pip \
		python3-dev \
		libffi-dev \
		openssl-dev \
	&& rm -f /var/cache/apk/*

# Install Terraform
COPY *-install /app/
RUN set -e \
	&& ./terraform-install '0.12.24' \
	&& ./credstash-install '0.4.1'

# Manage the Entrypoint
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
