# ./mail/Dockerfile
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Installer seulement Postfix (pas de SASL pour simplifier)
RUN apt-get update && \
    apt-get install -y \
    postfix \
    rsyslog \
    && rm -rf /var/lib/apt/lists/*

# Configuration Postfix ultra-simple
RUN echo "myhostname = mail.startup.tg" > /etc/postfix/main.cf && \
    echo "mydomain = startup.tg" >> /etc/postfix/main.cf && \
    echo "myorigin = \$mydomain" >> /etc/postfix/main.cf && \
    echo "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain" >> /etc/postfix/main.cf && \
    echo "relayhost =" >> /etc/postfix/main.cf && \
    echo "mynetworks = 172.20.0.0/24 127.0.0.0/8" >> /etc/postfix/main.cf && \
    echo "inet_interfaces = all" >> /etc/postfix/main.cf && \
    echo "inet_protocols = ipv4" >> /etc/postfix/main.cf

# Script de démarrage simple
RUN echo '#!/bin/bash' > /start.sh && \
    echo 'service rsyslog start' >> /start.sh && \
    echo 'service postfix start' >> /start.sh && \
    echo 'tail -f /var/log/mail.log' >> /start.sh && \
    chmod +x /start.sh

EXPOSE 25

CMD ["/start.sh"]