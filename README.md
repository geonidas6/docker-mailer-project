# 🚀 Guide : Traefik & Server Mail (SSL, SPF, DKIM, DMARC)

Ce guide explique comment configurer un projet avec **Traefik** (SSL automatique) et un **Serveur Mail** sécurisé pour obtenir un score de **10/10** sur [mail-tester.com](https://www.mail-tester.com).

## 1. Architecture Traefik (Docker Compose)

Traefik gère le SSL via Let's Encrypt et redirige le trafic vers vos services.

### Configuration Traefik
```yaml
  traefik:
    image: traefik:v3.0
    container_name: traefik
    restart: always
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
      - "--certificatesresolvers.myresolver.acme.email=admin@votre-domaine.com"
      - "--certificatesresolvers.myresolver.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.myresolver.acme.httpchallenge=true"
      - "--certificatesresolvers.myresolver.acme.httpchallenge.entrypoint=web"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./letsencrypt:/letsencrypt
```

### Exportation des Certificats pour le Mail
Le serveur mail a besoin des certificats SSL en format plat. On utilise `certs-exporter` :
```yaml
  certs-exporter:
    image: ldez/traefik-certs-dumper:v2.8.3
    container_name: certs_exporter
    volumes:
      - ./letsencrypt:/letsencrypt
      - ./certs:/output
    command: file --source /letsencrypt/acme.json --dest /output --watch --version v2
```

## 2. Serveur Mail (docker-mailserver)

### Configuration Docker Compose
```yaml
  mail:
    image: mailserver/docker-mailserver:latest
    container_name: mailserver
    hostname: mail
    domainname: votre-domaine.com
    environment:
      - ENABLE_SPAMASSASSIN=1
      - ENABLE_CLAMAV=1
      - ENABLE_POSTGREY=1
      - ENABLE_FAIL2BAN=1
      - SSL_TYPE=manual
      - SSL_CERT_PATH=/tmp/docker-mailserver/certs/certs/votre-domaine.com.crt
      - SSL_KEY_PATH=/tmp/docker-mailserver/certs/private/votre-domaine.com.key
    ports:
      - "25:25"
      - "587:587"
      - "143:143"
    volumes:
      - maildata:/var/mail
      - mailstate:/var/mail-state
      - ./config:/tmp/docker-mailserver
      - ./certs:/tmp/docker-mailserver/certs:ro
```

## 3. Configuration DNS (Cloudflare / Autre)

Pour éviter les spams, ces enregistrements sont **obligatoires** :

| Type | Nom | Valeur | Note |
| :--- | :--- | :--- | :--- |
| **A** | `mail` | `IP_DU_VPS` | DNS Uniquement (pas de proxy Cloudflare) |
| **MX** | `@` | `mail.votre-domaine.com` | Priorité : 10 |
| **TXT** | `@` | `v=spf1 ip4:IP_DU_VPS ~all` | Autorise le VPS à envoyer des mails |
| **TXT** | `_dmarc` | `v=DMARC1; p=none; rua=mailto:admin@votre-domaine.com` | Politique de sécurité |
| **TXT** | `mail._domainkey` | `v=DKIM1; k=rsa; p=CLE_PUBLIQUE_DKIM` | Signature des emails |

### Générer la clé DKIM
Une fois le conteneur `mail` lancé :
```bash
docker exec mailserver setup config dkim domain votre-domaine.com
```
Récupérez la clé publique dans `./config/opendkim/keys/votre-domaine.com/mail.txt`.

## 4. Reverse DNS (PTR)
**Indispensable pour Gmail/Outlook.**
1. Allez sur votre console VPS (OVH, DigitalOcean, etc.).
2. Modifiez le **Reverse DNS** de votre adresse IP.
3. Mettez le domaine principal : `votre-domaine.com`.

---
*Note: Utilisez `./setup_project.sh` pour automatiser toute cette configuration.*
