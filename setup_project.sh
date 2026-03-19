#!/bin/bash

PROJECT_NAME="fastapi_prod_project"
DOMAIN="api.it-sefako.com"
EMAIL="admin@api.it-sefako.com"

echo "📁 Création du projet..."
mkdir -p $PROJECT_NAME

# ========================
# docker-compose.yml
# ========================
cat > $PROJECT_NAME/docker-compose.yml <<EOL
services:

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
      - "--certificatesresolvers.myresolver.acme.email=${EMAIL}"
      - "--certificatesresolvers.myresolver.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.myresolver.acme.httpchallenge=true"
      - "--certificatesresolvers.myresolver.acme.httpchallenge.entrypoint=web"
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080" # dashboard
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./letsencrypt:/letsencrypt

  api:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: fastapi_app
    restart: always
    depends_on:
      - db
    environment:
      - DATABASE_URL=postgresql://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@db:5432/\${POSTGRES_DB}
      - SMTP_HOST=\${SMTP_HOST}
      - SMTP_PORT=\${SMTP_PORT}
      - SMTP_USER=\${SMTP_USER}
      - SMTP_PASSWORD=\${SMTP_PASSWORD}
      - SECRET_KEY=\${SECRET_KEY}
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.api.rule=Host(\`${DOMAIN}\`)"
      - "traefik.http.routers.api.entrypoints=websecure"
      - "traefik.http.routers.api.tls.certresolver=myresolver"
      - "traefik.http.services.api.loadbalancer.server.port=8000"
    expose:
      - "8000"

  certs-exporter:
    image: ldez/traefik-certs-dumper:v2.8.3
    container_name: certs_exporter
    volumes:
      - ./letsencrypt:/letsencrypt
      - ./certs:/output
    command: file --source /letsencrypt/acme.json --dest /output --watch --version v2

  db:
    image: postgres:15
    container_name: postgres_db
    restart: always
    environment:
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_DB: \${POSTGRES_DB}
    volumes:
      - postgres_data:/var/lib/postgresql/data

  mail:
    image: mailserver/docker-mailserver:latest
    container_name: mailserver
    restart: always
    hostname: mail
    domainname: ${DOMAIN}
    environment:
      - ENABLE_SPAMASSASSIN=1
      - ENABLE_CLAMAV=1
      - ENABLE_POSTGREY=1
      - ENABLE_FAIL2BAN=1
      - SSL_TYPE=manual
      - SSL_CERT_PATH=/tmp/docker-mailserver/certs/certs/${DOMAIN}.crt
      - SSL_KEY_PATH=/tmp/docker-mailserver/certs/private/${DOMAIN}.key
    ports:
      - "25:25"
      - "587:587"
      - "143:143"
    volumes:
      - maildata:/var/mail
      - mailstate:/var/mail-state
      - ./config:/tmp/docker-mailserver
      - ./certs:/tmp/docker-mailserver/certs:ro

volumes:
  postgres_data:
  maildata:
  mailstate:
EOL

# ========================
# Dockerfile
# ========================
cat > $PROJECT_NAME/Dockerfile <<EOL
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4"]
EOL

# ========================
# requirements.txt
# ========================
cat > $PROJECT_NAME/requirements.txt <<EOL
fastapi
uvicorn
psycopg2-binary
sqlalchemy
asyncpg
python-dotenv
EOL

# ========================
# main.py
# ========================
cat > $PROJECT_NAME/main.py <<EOL
from fastapi import FastAPI
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.utils import formataddr
import os
import smtplib

app = FastAPI()

SMTP_HOST = os.getenv("SMTP_HOST", "mail")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER = os.getenv("SMTP_USER", "")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "")

def send_email(to_email: str, subject: str, text_body: str, html_body: str | None = None):
    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = formataddr(("IT-Sefako", SMTP_USER))
    msg["To"] = to_email
    
    msg.attach(MIMEText(text_body, "plain"))
    if html_body:
        msg.attach(MIMEText(html_body, "html"))

    with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
        server.ehlo()
        server.starttls()
        server.ehlo()
        if SMTP_USER and SMTP_PASSWORD:
            server.login(SMTP_USER, SMTP_PASSWORD)
        server.send_message(msg)

@app.get("/")
def read_root():
    return {"message": "FastAPI + Traefik OK 🚀"}

@app.get("/test-email")
def test_email(email: str = "geonidas6@gmail.com"):
    subject = "Confirmation de test technique - It-Sefako"
    text = "Ceci est un test de configuration de votre serveur de messagerie. Si vous recevez ce message, votre configuration est correcte."
    html = f"""
    <html>
      <body>
        <h2 style='color: #2e6c80;'>Félicitations !</h2>
        <p>Votre serveur FastAPI à l'adresse <b>{os.getenv("DOMAIN", "api.it-sefako.com")}</b> est maintenant capable d'envoyer des emails sécurisés.</p>
        <p>Ce message a été envoyé avec une signature <b>DKIM</b> valide et respecte les protocoles <b>SPF</b> et <b>DMARC</b>.</p>
        <hr>
        <p style='font-size: 10px; color: grey;'>Ceci est un message automatique de test.</p>
      </body>
    </html>
    """
    send_email(email, subject, text, html)
    return {"status": f"email envoyé à {email}"}
EOL

# ========================
# .env
# ========================
cat > $PROJECT_NAME/.env <<EOL
POSTGRES_USER=produser
POSTGRES_PASSWORD=StrongPass123!
POSTGRES_DB=prod_db

SMTP_HOST=mail
SMTP_PORT=587
SMTP_USER=contact@${DOMAIN}
SMTP_PASSWORD=motdepasse123

SECRET_KEY=YourSuperSecretKey123!
EOL

# ========================
# letsencrypt dossier
# ========================
if [ ! -f "fastapi_prod_project/letsencrypt/acme.json" ] || [ ! -s "fastapi_prod_project/letsencrypt/acme.json" ]; then
    mkdir -p fastapi_prod_project/letsencrypt
    touch fastapi_prod_project/letsencrypt/acme.json
    chmod 600 fastapi_prod_project/letsencrypt/acme.json
    echo "📁 Fichier acme.json initialisé."
else
    echo "📁 Fichier acme.json déjà présent et non vide, conservation."
fi

# ========================
# Mailserver config
# ========================
if [ ! -d "fastapi_prod_project/config" ] || [ -z "$(ls -A fastapi_prod_project/config 2>/dev/null)" ]; then
    mkdir -p fastapi_prod_project/config
    echo "📁 Configuration initiale du serveur mail..."
    docker compose -f fastapi_prod_project/docker-compose.yml up -d mail
    sleep 15
    docker exec mailserver setup email add contact@${DOMAIN} motdepasse123
    docker exec mailserver setup config dkim domain ${DOMAIN}
    echo "📁 Clés DKIM générées."
else
    echo "📁 Dossier config déjà présent, conservation des clés DKIM."
fi

echo "✅ Projet Traefik prêt !"
echo "➡️ Lance avec : cd $PROJECT_NAME && docker compose up -d"
echo ""
echo "⚠️ IMPORTANT : Pour un score 10/10 et éviter les spams, ajoute ces records DNS dans Cloudflare :"
echo "1️⃣ A Record : (Nom: mail.${DOMAIN%%.*}) Valeur: $(curl -s https://api.ipify.org) (DNS Uniquement)"
echo "2️⃣ MX Record : (Nom: ${DOMAIN%%.*}) Valeur: mail.${DOMAIN}. (Priorité: 10)"
echo "3️⃣ SPF TXT : (Nom: ${DOMAIN%%.*}) v=spf1 ip4:$(curl -s https://api.ipify.org) ~all"
echo "4️⃣ DKIM TXT : (Nom: mail._domainkey.${DOMAIN%%.*}) Recopie la valeur ci-dessous :"
docker exec mailserver cat /tmp/docker-mailserver/opendkim/keys/${DOMAIN}/mail.txt | tr -d '\n\t ' | sed 's/.*(\(.*\)).*/\1/;s/"//g'
echo ""
echo "5️⃣ DMARC TXT : (Nom: _dmarc.${DOMAIN%%.*}) v=DMARC1; p=none; rua=mailto:admin@${DOMAIN}"
echo ""
echo "🌍 REVERSE DNS (PTR) : Connecte-toi sur ton tableau de bord VPS (OVH/etc.)"
echo "   et règle le Reverse DNS de ton IP ($(curl -s https://api.ipify.org)) sur : $DOMAIN"
