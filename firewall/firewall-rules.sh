#!/bin/sh

# Réinitialisation des règles
iptables -F
iptables -X

# Politiques par défaut
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Autoriser le trafic interne
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -s 172.20.0.0/24 -j ACCEPT

# Autoriser les ports nécessaires
iptables -A INPUT -p tcp --dport 80 -j ACCEPT   # HTTP 
iptables -A INPUT -p tcp --dport 8000 -j ACCEPT 
iptables -A INPUT -p tcp --dport 443 -j ACCEPT  # HTTPS
iptables -A INPUT -p udp --dport 53 -j ACCEPT   # DNS
iptables -A INPUT -p tcp --dport 53 -j ACCEPT   # DNS