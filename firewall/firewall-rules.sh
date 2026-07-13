#!/bin/sh
set -e

# Ce conteneur tourne en network_mode: host (cf. docker-compose.yml) afin de
# pouvoir écrire dans la chaîne DOCKER-USER de l'hôte. Cette chaîne est
# consultée par Docker AVANT ses propres règles FORWARD "ACCEPT tout" : c'est
# le seul point où l'on peut réellement filtrer le trafic entrant/sortant des
# conteneurs (source/destination) plutôt que le trafic du firewall lui-même.
# Nécessite un hôte Linux (Docker Desktop Windows/Mac : voir README).

INTERNAL_NET="172.20.0.0/24"
DB_IP="172.20.0.10"
WEB_IP="172.20.0.20"
MAIL_IP="172.20.0.30"
DNS_IP="172.20.0.40"
NGINX_IP="172.20.0.50"

echo "[firewall] (ré)application de la politique de sécurité sur DOCKER-USER"

# Repart d'une chaîne DOCKER-USER vierge à chaque (re)démarrage.
iptables -F DOCKER-USER 2>/dev/null || iptables -N DOCKER-USER

# --- Politique par défaut du conteneur firewall lui-même (host network) ---
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# --- Connexions déjà établies : toujours autorisées ---
iptables -A DOCKER-USER -m state --state ESTABLISHED,RELATED -j ACCEPT

# --- Trafic interne (conteneur à conteneur) : autorisé ---
# (web -> db, web -> mail, etc. Le filtrage "DB non accessible depuis
# l'extérieur" est déjà assuré par le fait qu'aucun port n'est publié pour
# db dans docker-compose.yml ; les règles ci-dessous protègent en plus
# contre une republication accidentelle du port.)
iptables -A DOCKER-USER -s "$INTERNAL_NET" -d "$INTERNAL_NET" -j ACCEPT

# --- Services exposés depuis l'extérieur : Web (HTTP/HTTPS) ---
iptables -A DOCKER-USER -p tcp -d "$NGINX_IP" --dport 80  -j ACCEPT
iptables -A DOCKER-USER -p tcp -d "$NGINX_IP" --dport 443 -j ACCEPT

# --- Services exposés depuis l'extérieur : DNS ---
iptables -A DOCKER-USER -p tcp -d "$DNS_IP" --dport 53 -j ACCEPT
iptables -A DOCKER-USER -p udp -d "$DNS_IP" --dport 53 -j ACCEPT

# --- Services exposés depuis l'extérieur : Mail (SMTP/Submission/SMTPS) ---
iptables -A DOCKER-USER -p tcp -d "$MAIL_IP" --dport 25  -j ACCEPT
iptables -A DOCKER-USER -p tcp -d "$MAIL_IP" --dport 587 -j ACCEPT
iptables -A DOCKER-USER -p tcp -d "$MAIL_IP" --dport 465 -j ACCEPT

# --- Base de données : jamais accessible depuis l'extérieur ---
iptables -A DOCKER-USER -d "$DB_IP" -j LOG --log-prefix "FW-DROP-DB: " --log-level 4 -m limit --limit 5/min
iptables -A DOCKER-USER -d "$DB_IP" -j DROP

# --- Tout le reste à destination du réseau applicatif : refusé et journalisé ---
iptables -A DOCKER-USER -d "$INTERNAL_NET" -j LOG --log-prefix "FW-DROP: " --log-level 4 -m limit --limit 5/min
iptables -A DOCKER-USER -d "$INTERNAL_NET" -j DROP

echo "[firewall] politique appliquée :"
iptables -L DOCKER-USER -n -v

# Le conteneur reste actif pour conserver les règles tant qu'il tourne
# (redémarrage automatique de Docker s'il s'arrête, cf. restart: unless-stopped).
tail -f /dev/null
