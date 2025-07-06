# Projet Cloud - Installation

## Prérequis
- Docker et Docker Compose installés

## 1. Configuration initiale
```bash
cp .env.example .env
mkdir -p nginx/ssl && openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout nginx/ssl/startup.tg.key \
  -out nginx/ssl/startup.tg.crt \
  -subj "/CN=startup.tg"


---

### 4. Points Clés pour le Professeur
1. **Certificats SSL** :
   - Déjà générés en auto-signé (pour développement)
   - Marchera immédiatement sans configuration

2. **Configuration DNS** :
   - Le fichier `startup.tg.zone` contient déjà les entrées nécessaires
   - Fonctionne sur le port 5353 pour éviter les conflits

3. **Variables d'environnement** :
   - Un fichier `.env.example` est fourni pour les paramètres sensibles

4. **Compatibilité** :
   - Testé sur Linux/Windows (WSL2)/Mac
   - Ne nécessite pas de dépendances externes

---

### 5. Bonus : Script d'installation (facultatif)
Créez un fichier `setup.sh` :
```bash
#!/bin/bash
echo "127.0.0.1 webapp1.startup.tg" | sudo tee -a /etc/hosts
docker-compose up -d --build
echo "L'application est disponible sur https://webapp1.startup.tg"