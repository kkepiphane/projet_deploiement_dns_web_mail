FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    postfix \
    postfix-pcre \
    sasl2-bin \
    libsasl2-modules \
    mailutils \
    rsyslog \
    opendkim \
    opendkim-tools && \
    rm -rf /var/lib/apt/lists/*

# Configure SASL (authentification pour la soumission 587 / SMTPS 465)
RUN mkdir -p /etc/postfix/sasl && \
    echo "pwcheck_method: auxprop" > /etc/postfix/sasl/smtpd.conf && \
    echo "auxprop_plugin: sasldb" >> /etc/postfix/sasl/smtpd.conf && \
    echo "mech_list: PLAIN LOGIN" >> /etc/postfix/sasl/smtpd.conf

# Configure Postfix
COPY postfix/main.cf postfix/master.cf /etc/postfix/
COPY postfix/virtual_aliases /etc/postfix/virtual_aliases
RUN postmap /etc/postfix/virtual_aliases && \
    chmod 600 /etc/postfix/virtual_aliases.db && \
    newaliases && \
    chown root:postfix /etc/postfix/sasl/smtpd.conf && \
    chmod 640 /etc/postfix/sasl/smtpd.conf

# Configure OpenDKIM (signature des mails sortants pour startup.tg)
COPY postfix/opendkim.conf /etc/opendkim.conf
RUN mkdir -p /etc/opendkim/keys /run/opendkim && \
    opendkim-genkey -D /etc/opendkim/keys/ -d startup.tg -s mail && \
    chown -R opendkim:opendkim /etc/opendkim/keys /run/opendkim && \
    chmod 600 /etc/opendkim/keys/mail.private && \
    adduser postfix opendkim

EXPOSE 25 587 465

# Pas d'init système dans le conteneur : on démarre les démons directement
# (rsyslogd/opendkim se forkent en arrière-plan) puis postfix reste au
# premier plan pour maintenir le conteneur actif.
CMD sh -c "rsyslogd; opendkim -x /etc/opendkim.conf -u opendkim -P /run/opendkim/opendkim.pid; postfix start-fg"
