FROM ubuntu:22.04

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    postfix \
    postfix-pcre \
    opendkim \
    opendkim-tools \
    mailutils \
    libsasl2-modules && \
    rm -rf /var/lib/apt/lists/*

# Configuration de base
RUN echo "mail.startup.tg" > /etc/mailname && \
    postconf -e "myhostname = mail.startup.tg" && \
    postconf -e "mydomain = startup.tg"

# Créer le répertoire sasl s'il n'existe pas
RUN mkdir -p /etc/postfix/sasl

COPY postfix/ /etc/postfix/

# Vérifier l'existence des fichiers avant de les modifier
RUN if [ -f "/etc/postfix/virtual_aliases" ]; then \
        postmap /etc/postfix/virtual_aliases && \
        chmod 600 /etc/postfix/virtual_aliases.db; \
    fi && \
    if [ -f "/etc/postfix/sasl/smtpd.conf" ]; then \
        chown root:postfix /etc/postfix/sasl/smtpd.conf && \
        chmod 640 /etc/postfix/sasl/smtpd.conf; \
    fi && \
    chmod -R o-rwx /etc/postfix

EXPOSE 25 587

CMD ["sh", "-c", "service postfix start && tail -f /var/log/mail.log"]