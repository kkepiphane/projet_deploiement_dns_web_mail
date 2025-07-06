FROM alpine:3.18

RUN apk add --no-cache iptables ip6tables

COPY firewall-rules.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/firewall-rules.sh

CMD ["/usr/local/bin/firewall-rules.sh"]