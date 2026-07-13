# Startup TG — Déploiement de microservices (DNS / Web / Mail / DB / Pare-feu)

Infrastructure conteneurisée pour le domaine **startup.tg**, réalisée dans le cadre du projet
UCAO *"Déploiement de microservices"*. Cinq services Docker collaborent :
**Base de données** (PostgreSQL), **Web** (Django + Nginx), **Mail** (Postfix + OpenDKIM),
**DNS** (BIND9) et **Pare-feu** (iptables), reliés par un réseau interne et une politique de
sécurité qui limite ce qui est joignable depuis l'extérieur.

Ce document a été réécrit après un audit complet du dépôt : chaque service a été testé
individuellement (build, démarrage, comportement réel), plusieurs bugs bloquants ont été
corrigés, et la configuration a été alignée sur le sujet du projet. La section
[Ce qui a été corrigé](#ce-qui-a-été-corrigé) détaille précisément ce qui ne fonctionnait pas.

## Sommaire

- [Démarrage rapide](#démarrage-rapide)
- [Plan d'adressage](#plan-daddressage)
- [Architecture](#architecture)
- [Politique de sécurité (pare-feu)](#politique-de-sécurité-pare-feu)
- [Tester chaque service](#tester-chaque-service)
- [Montée en charge dynamique](#montée-en-charge-dynamique)
- [Conformité au sujet du projet](#conformité-au-sujet-du-projet)
- [Ce qui a été corrigé](#ce-qui-a-été-corrigé)
- [Limites connues](#limites-connues)
- [Aspects budget / équipe](#aspects-budget--équipe)

## Démarrage rapide

### Prérequis

- Docker Engine + Docker Compose v2 (`docker compose version`)
- **Un hôte Linux** pour que le pare-feu soit pleinement effectif (voir
  [Politique de sécurité](#politique-de-sécurité-pare-feu)) — fonctionne aussi sur Docker
  Desktop (Windows/macOS) pour le reste de la stack.
- Le sous-réseau `172.20.0.0/24` (défini dans `docker-compose.yml`) ne doit pas entrer en
  conflit avec un réseau Docker existant sur la machine (`docker network inspect $(docker
  network ls -q)` pour vérifier). En cas de conflit, changez la valeur de `subnet:` et les
  adresses `ipv4_address:` correspondantes (et le fichier de zone DNS).
- Le port **53** (DNS) ne doit pas déjà être occupé sur l'hôte (service `systemd-resolved` sur
  certaines distributions Linux, par exemple).

### Lancer l'application

```bash
docker compose up -d --build
```

Cela démarre : `db`, `dns`, `web`, `nginx`, `mail`, `firewall`. Le service `mailhog` (boîte de
réception SMTP de test, pratique en développement) est optionnel et ne démarre qu'avec le
profil `dev` :

```bash
docker compose --profile dev up -d
```

Dans ce cas, positionnez `EMAIL_HOST=mailhog` et `EMAIL_PORT=1025` dans `.env` avant de
démarrer `web`, pour que Django envoie ses mails vers MailHog plutôt que vers Postfix
(interface web de consultation sur http://localhost:8025).

L'application est accessible sur :
- http://webapp1.startup.tg (ou http://localhost, ou https://localhost avec le certificat
  auto-signé fourni)
- Ajoutez `webapp1.startup.tg` à votre fichier `hosts` local pointant vers l'IP du serveur, ou
  interrogez le DNS du projet (`dig @<ip-serveur> webapp1.startup.tg`).

### Arrêt

```bash
docker compose down        # -v pour supprimer aussi les volumes (⚠️ perte des données)
```

## Plan d'adressage

Réseau interne Docker : `172.20.0.0/24`

| Service    | Conteneur           | IP interne    | Ports publiés (hôte)          | Accessible depuis l'extérieur |
|------------|----------------------|---------------|--------------------------------|-------------------------------|
| Base de données | `db`            | 172.20.0.10   | *(aucun)*                      | ❌ Non — jamais publié |
| Web (Django)    | `web` *(réplicable)* | dynamique | *(aucun, derrière nginx)*      | ❌ Non — uniquement via nginx |
| Mail       | `mail`               | 172.20.0.30   | 25, 587, 465                   | ✅ Oui |
| MailHog (dev)   | `mailhog`        | 172.20.0.31   | 8025 (interface web)           | Dev uniquement (profil `dev`) |
| DNS        | `dns`                | 172.20.0.40   | 53/tcp, 53/udp                 | ✅ Oui |
| Nginx (reverse proxy) | `nginx`   | 172.20.0.50   | 80, 443                        | ✅ Oui |
| Pare-feu   | `firewall`           | *(réseau hôte)* | —                            | — (n'expose rien, filtre) |

`web` n'a volontairement **pas d'IP fixe** : c'est une condition nécessaire pour pouvoir le
répliquer (`docker compose up --scale web=N`). nginx s'appuie sur le nom de service `web` et le
DNS interne de Docker pour répartir la charge entre les instances.

## Architecture

```
                                   Internet
                                      │
                    ┌─────────────────┼─────────────────┐
                    │                 │                 │
                 :80/:443           :53               :25/:587/:465
                    │                 │                 │
              ┌─────▼─────┐     ┌─────▼─────┐     ┌─────▼─────┐
              │   nginx   │     │    dns    │     │   mail    │
              │ 172.20.0.50│    │172.20.0.40│     │172.20.0.30│
              └─────┬─────┘     └───────────┘     └───────────┘
                    │ proxy_pass (nom de service)
              ┌─────▼─────┐
              │    web    │  (répliqué, pas d'IP fixe)
              │  Django   │
              └─────┬─────┘
                    │
              ┌─────▼─────┐
              │     db    │  172.20.0.10 — jamais publié, jamais résolu publiquement
              │ PostgreSQL│
              └───────────┘

   firewall (network_mode: host) : filtre le trafic entre l'extérieur et le réseau
   172.20.0.0/24 via la chaîne iptables DOCKER-USER de l'hôte.
```

*(Pour le livrable demandé par le sujet — topologie sous Dia exportée en PNG — reprendre ce
schéma dans l'outil Dia.)*

## Politique de sécurité (pare-feu)

Le sujet impose : *"le pare-feu permet de filtrer les requêtes en fonction de leur source et de
leur destination"* et *"certains services sont accessibles depuis l'extérieur (Web, Mail, DNS)
et d'autres non (Base de données)"*.

Un conteneur Docker "à côté" des autres sur un réseau bridge **ne se trouve pas sur le chemin**
du trafic des autres conteneurs : des règles iptables appliquées uniquement dans son propre
namespace réseau ne filtrent que son propre trafic, pas celui de `web`, `db`, etc. C'était le
bug principal de la version précédente (voir [Ce qui a été corrigé](#ce-qui-a-été-corrigé)).

Pour filtrer réellement le trafic inter-conteneurs, `firewall` tourne en
`network_mode: host` et écrit ses règles dans la chaîne **`DOCKER-USER`** de l'hôte — la seule
chaîne que Docker consulte *avant* ses propres règles `FORWARD` "tout autoriser". C'est la
méthode recommandée par la documentation Docker pour pare-feuter des conteneurs.
Cela nécessite un hôte Linux (Docker Desktop Windows/macOS tourne dans une VM Linux ; les
règles s'appliquent mais uniquement à l'intérieur de cette VM).

Règles appliquées par `firewall/firewall-rules.sh` (rejouées à chaque démarrage) :

| Source        | Destination         | Port(s)          | Action |
|----------------|----------------------|-------------------|--------|
| n'importe où   | connexions établies  | —                 | ACCEPT |
| 172.20.0.0/24  | 172.20.0.0/24        | tout              | ACCEPT (trafic inter-services légitime, ex. web → db) |
| n'importe où   | nginx (172.20.0.50)  | 80, 443           | ACCEPT |
| n'importe où   | dns (172.20.0.40)    | 53 (tcp+udp)      | ACCEPT |
| n'importe où   | mail (172.20.0.30)   | 25, 587, 465      | ACCEPT |
| n'importe où   | db (172.20.0.10)     | tout              | **DROP + LOG** |
| n'importe où   | 172.20.0.0/24 (reste)| tout              | **DROP + LOG** (politique par défaut) |

La non-publication du port de `db` dans `docker-compose.yml` est la première ligne de défense ;
les règles `DOCKER-USER` sont une défense en profondeur en cas de republication accidentelle,
et documentent explicitement la politique demandée par le sujet.

## Tester chaque service

### Web
```bash
curl -I http://localhost/                 # 200
curl -Ik https://localhost/                # 200 (certificat auto-signé)
curl -I http://localhost/admin/login/      # 200, CSS admin chargé (fichiers statiques OK)
```
Le formulaire de contact (page d'accueil ou `/contact/`) écrit en base (`app_contact`) et
envoie un mail à `contact@startup.tg` ou `info@startup.tg` selon le destinataire choisi.

### Base de données
```bash
docker exec -it startup_tg-db-1 psql -U admin -d appdb -c "\dt"
docker exec -it startup_tg-db-1 psql -U admin -d appdb -c "SELECT * FROM app_contact;"
```
Vérifiez qu'aucun port `5432` n'est publié : `docker compose ps db` (colonne PORTS vide).

### DNS
```bash
dig @<ip-ou-localhost> webapp1.startup.tg +short     # 172.20.0.50
dig @<ip-ou-localhost> startup.tg MX +short           # 10 mail.startup.tg.
dig @<ip-ou-localhost> db.startup.tg +short            # (aucune réponse : non publié)
```

### Mail
```bash
# Test SMTP direct (queue + livraison locale)
swaks --to contact@startup.tg --from test@example.com --server localhost --port 25 \
      --body "Test" --header "Subject: Test"

# Vérifier la livraison (alias virtuel contact@/info@ -> boîte système "root")
docker exec startup_tg-mail-1 tail -n 30 /var/mail/root
docker exec startup_tg-mail-1 tail -n 30 /var/log/mail.log
```
En profil `dev`, consultez plutôt http://localhost:8025 (MailHog).

### Pare-feu
```bash
docker logs startup_tg-firewall-1          # doit afficher la table DOCKER-USER appliquée
sudo iptables -L DOCKER-USER -n -v          # depuis l'hôte Linux
# journal des paquets refusés vers db :
sudo dmesg | grep FW-DROP-DB
```

## Montée en charge dynamique

Le sujet demande : *"le nombre d'instances de chaque service augmente dynamiquement afin de
s'adapter au pic de montée en charge"*.

Docker Compose seul ne fait pas d'auto-scaling réactif à la charge — il faut Docker Swarm
(`docker service scale` / `docker service update --replicas`) ou Kubernetes (HPA) pour une
vraie boucle d'autoscaling pilotée par métriques. Ce dépôt fournit la brique nécessaire côté
architecture (services sans IP fixe, découverte via DNS interne, `deploy.resources.limits`)
pour que la montée en charge **manuelle ou orchestrée** fonctionne sans changement de code :

```bash
# montée en charge manuelle avec docker compose
docker compose up -d --scale web=4

# avec Docker Swarm (déploiement du même fichier en mode stack)
docker swarm init
docker stack deploy -c docker-compose.yml startup_tg
docker service scale startup_tg_web=4
```

⚠️ Au tout premier démarrage, laissez `web` tourner en 1 réplique le temps que les migrations
Django s'appliquent (`docker compose up -d web`), puis montez en charge — plusieurs instances
lancées simultanément sur une base vide pourraient exécuter `migrate` en concurrence.

## Conformité au sujet du projet

| Exigence du sujet | État |
|---|---|
| Conteneurisation des 5 services (DB, Web, Mail, DNS, Pare-feu) | ✅ |
| Web accessible via `webapp1.startup.tg` | ✅ (HTTP + HTTPS) |
| Mail : envoi/réception via `contact@` et `info@startup.tg` | ✅ (Postfix, testé de bout en bout) |
| DNS : résolution de `startup.tg` | ✅ (port standard 53) |
| Connectivité interne + externe | ✅ |
| Politique de sécurité définissant trafic autorisé/refusé | ✅ (chaîne `DOCKER-USER`, voir ci-dessus) |
| Pare-feu filtrant par source/destination | ✅ |
| DB non accessible depuis l'extérieur, Web/Mail/DNS accessibles | ✅ |
| Montée en charge dynamique | ⚠️ Manuelle/orchestrée (Compose seul ne fait pas d'autoscaling réactif, voir ci-dessus) |
| Plan d'adressage | ✅ (voir ci-dessus) |
| Topologie réseau (Dia, export PNG) | 📋 À produire séparément à partir du schéma de ce README |
| Considérations budget/équipe/sécurité | ✅ voir [Aspects budget / équipe](#aspects-budget--équipe) |

## Ce qui a été corrigé

L'audit a démarré, testé et volontairement fait échouer chaque service pour vérifier ce qui
fonctionnait réellement. Bugs bloquants trouvés et corrigés :

- **`web` n'avait pas `env_file: .env`** dans `docker-compose.yml` → Django ne pouvait jamais
  s'authentifier auprès de PostgreSQL (`fe_sendauth: no password supplied`).
- **Aucune migration Django n'existait** pour le modèle `Contact` → même en corrigeant la
  connexion, la table n'existait pas. `db/init.sql` créait une table `users` sans rapport,
  jamais utilisée par l'application.
- **`settings.ADMIN_EMAIL` n'était pas défini** alors que `views.py` s'y référait → toute
  soumission du formulaire de contact levait une `AttributeError`.
- **`views.contact()` rendait `app/contact.html`**, un template qui n'existe pas (le vrai
  fichier est `contact/contact.html`) → `/contact/` renvoyait une 500 depuis toujours,
  indépendamment de tout le reste.
- **Le formulaire de contact de la page d'accueil était purement côté client** (`preventDefault`
  + `alert()`), il ne postait jamais vers Django ; et `/contact/` n'avait **aucun `<form>`** du
  tout. Les deux surfaces de contact ont été reliées au backend.
- **`firewall-rules.sh` était encodé en CRLF** (fins de ligne Windows) → le shebang cassait dans
  le conteneur Alpine (`exec: no such file or directory`) → le conteneur redémarrait en boucle
  → **aucune règle de pare-feu n'était jamais appliquée**. Corrigé (LF + `.gitattributes` pour
  empêcher la régression), et le script a été réécrit pour cibler `DOCKER-USER` (voir
  [Politique de sécurité](#politique-de-sécurité-pare-feu)), car même corrigé, l'ancien script ne
  filtrait que le trafic du conteneur `firewall` lui-même, pas celui des autres services.
- **Le vrai Dockerfile Postfix/SASL/OpenDKIM (avec 587/465) se trouvait par erreur dans
  `dns/Dockerfile`** — un fichier que le service `dns` n'utilise même pas (il tourne sur l'image
  `ubuntu/bind9` toute faite). `mail/Dockerfile` ne contenait qu'une ébauche minimale (port 25
  seul, sans SASL ni DKIM). Le service `mail` était en plus commenté dans `docker-compose.yml`,
  remplacé par MailHog (outil de test, pas un vrai serveur de messagerie). Le Dockerfile complet
  a été déplacé au bon endroit, son script de démarrage corrigé (il utilisait `service rsyslog
  start` / `service saslauthd start`, deux commandes qui échouaient systématiquement dans ce
  conteneur minimal sans init system), et les fichiers de configuration Postfix manquants
  (`main.cf`, `master.cf`, `virtual_aliases` pour `contact@`/`info@`, `opendkim.conf`) ont été
  créés. Testé de bout en bout : réception SMTP, alias virtuel, livraison en boîte locale.
- **`nginx/conf.d/default.conf` pointait vers l'IP fixe `172.20.0.20`** au lieu du nom de
  service `web` → cassait dès que l'IP changeait, et rendait toute réplication de `web`
  impossible (deux conteneurs ne peuvent pas partager la même IP fixe). Passé à la résolution
  DNS interne de Docker (`server web:8000`), ce qui permet en plus la répartition de charge
  entre répliques.
- **`web` avait une IP fixe (`ipv4_address`)**, incompatible avec `--scale` : supprimée.
- **Bind mount `./web:/app` masquait les fichiers statiques collectés au build** (le dossier
  hôte `web/staticfiles` était vide, et nginx pointait dessus) → CSS admin et fichiers statiques
  jamais servis. Remplacé par un volume nommé partagé (`static_volume`), régénéré au démarrage
  du conteneur.
- **Le port DNS était publié sur `5353` au lieu de `53`** → ne satisfaisait pas l'exigence
  "DNS accessible depuis l'extérieur" avec les résolveurs standards.
- **La zone DNS publiait un enregistrement A pour `db.startup.tg`** → une base censée être
  inaccessible depuis l'extérieur voyait quand même son IP interne divulguée publiquement.
  Supprimé.
- **Certificats TLS présents (`nginx/ssl/`) mais jamais utilisés** → nginx n'écoutait que sur le
  port 80 alors que le README promettait `https://`. Ajout d'un bloc serveur 443.
- `about.html` (template vide, non routé) supprimé ; `__pycache__` retiré du suivi Git et
  `.gitignore`/`.gitattributes` ajoutés ; `nginx.conf` à la racine (doublon mort, jamais monté
  par `docker-compose.yml`) supprimé ; avertissement Compose `version` obsolète supprimé ;
  `depends_on` de `web` passé en `condition: service_healthy` pour éviter une course au
  démarrage avec PostgreSQL.

## Limites connues

- **Autoscaling réactif** : non implémenté nativement par Docker Compose (voir
  [Montée en charge dynamique](#montée-en-charge-dynamique)) — nécessite Swarm ou Kubernetes
  pour une boucle automatique basée sur des métriques (CPU, requêtes/s).
- **Authentification SASL du serveur mail** : la configuration Cyrus SASL est en place (port
  587/465, TLS), mais aucun utilisateur n'est créé par défaut dans `sasldb2` (choix volontaire :
  éviter de coder un mot de passe en dur dans l'image). À créer manuellement :
  `docker exec -it startup_tg-mail-1 saslpasswd2 -c <utilisateur>`.
- **DNS haute disponibilité** : une seule instance BIND9 (maître, sans secondaire) — suffisant
  pour la démonstration, à renforcer en production (serveur secondaire, `allow-transfer` dédié).
- **Isolation firewall sous Docker Desktop (Windows/macOS)** : les règles `DOCKER-USER`
  s'appliquent bien (testé), mais dans la VM Linux gérée par Docker Desktop plutôt que sur le
  système d'exploitation hôte directement. En déploiement réel sur un serveur Linux, le
  comportement est identique et pleinement en bordure de réseau.

## Aspects budget / équipe

Le sujet demande une réflexion sur les aspects matériels/logiciels, financiers et humains du
projet. Éléments de cadrage (à détailler dans le rapport de projet) :

- **Matériel/logiciel** : stack 100% open-source (PostgreSQL, Nginx, Postfix, BIND9,
  Django, Docker) — pas de coût de licence. Dimensionnement à adapter selon la charge réelle
  (`deploy.resources.limits` dans `docker-compose.yml` comme point de départ).
- **Financier** : coût principal = hébergement (VM ou serveur dédié Linux pour bénéficier
  pleinement du pare-feu `DOCKER-USER`), nom de domaine `startup.tg`, certificat TLS (le dépôt
  fournit un certificat auto-signé à remplacer par un certificat signé — Let's Encrypt par
  exemple — en production).
- **Humain** : répartition suggérée par service (une personne ou binôme par microservice :
  DB/Web/Mail/DNS/Pare-feu) avec un rôle transverse pour l'intégration `docker-compose.yml` et
  la politique de sécurité, qui touche tous les services.
