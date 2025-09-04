FROM ubuntu:22.04

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    postfix \
    postfix-pcre \
    sasl2-bin \
    libsasl2-modules \
    mailutils \
    opendkim \
    opendkim-tools && \
    rm -rf /var/lib/apt/lists/*

# Configure SASL
RUN mkdir -p /etc/postfix/sasl && \
    echo "pwcheck_method: auxprop" > /etc/postfix/sasl/smtpd.conf && \
    echo "auxprop_plugin: sasldb" >> /etc/postfix/sasl/smtpd.conf && \
    echo "mech_list: PLAIN LOGIN" >> /etc/postfix/sasl/smtpd.conf

# Configure Postfix
COPY postfix/ /etc/postfix/
RUN postmap /etc/postfix/virtual_aliases && \
    chmod 600 /etc/postfix/virtual_aliases.db && \
    chown root:postfix /etc/postfix/sasl/smtpd.conf && \
    chmod 640 /etc/postfix/sasl/smtpd.conf

# Configure OpenDKIM
RUN mkdir -p /etc/opendkim/keys && \
    opendkim-genkey -D /etc/opendkim/keys/ -d startup.tg -s mail && \
    chown opendkim:opendkim /etc/opendkim/keys/mail.private

EXPOSE 25 587 465

CMD service saslauthd start && \
    service opendkim start && \
    service postfix start && \
    tail -f /var/log/mail.log