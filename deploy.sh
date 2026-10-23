#!/usr/bin/env bash
# DinoFace Battle 배포 (서버에서 root로 실행)
# /var/www/dino.revuplan.com 과 nginx의 dino.revuplan.com 전용 설정만 추가합니다. 기존 사이트는 건드리지 않습니다.
set -euo pipefail
cd "$(dirname "$0")"
DOMAIN=dino.revuplan.com
WEBROOT=/var/www/$DOMAIN

command -v nginx >/dev/null || { echo "!! nginx가 없습니다. 웹서버 종류를 알려주세요."; exit 1; }

echo "[1/5] 파일 복사 → $WEBROOT"
mkdir -p "$WEBROOT"
cp -f index.html "$WEBROOT/index.html"
if [ ! -s "$WEBROOT/three.min.js" ]; then
  curl -fsSL https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js -o "$WEBROOT/three.min.js"
fi
chown -R www-data:www-data "$WEBROOT" 2>/dev/null || chown -R nginx:nginx "$WEBROOT" 2>/dev/null || true

echo "[2/5] 도메인 중복 확인"
if grep -RqsE "server_name[^;]*\b$DOMAIN\b" /etc/nginx/ --exclude="*$DOMAIN*"; then
  echo "!! 이미 다른 설정에서 $DOMAIN 을 사용 중입니다. 중단합니다."; exit 1
fi

echo "[3/5] nginx 설정 작성"
CONF='server {
    listen 80;
    listen [::]:80;
    server_name dino.revuplan.com;
    root /var/www/dino.revuplan.com;
    index index.html;
    location / { try_files $uri $uri/ =404; }
    location ~* \.(js|png|jpg|webp|svg|ico)$ { expires 7d; add_header Cache-Control "public"; }
    gzip on;
    gzip_types text/html text/css application/javascript;
}'
if [ -d /etc/nginx/sites-available ] && grep -q "sites-enabled" /etc/nginx/nginx.conf; then
  echo "$CONF" > /etc/nginx/sites-available/$DOMAIN
  ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/$DOMAIN
  NEWCONF=/etc/nginx/sites-enabled/$DOMAIN
else
  echo "$CONF" > /etc/nginx/conf.d/$DOMAIN.conf
  NEWCONF=/etc/nginx/conf.d/$DOMAIN.conf
fi

echo "[4/5] nginx 문법 검사 후 무중단 reload"
if ! nginx -t; then
  echo "!! 설정 오류 → 방금 추가한 설정을 되돌립니다 (기존 사이트 영향 없음)"
  rm -f "$NEWCONF" /etc/nginx/sites-available/$DOMAIN
  exit 1
fi
systemctl reload nginx || nginx -s reload

echo "[5/5] HTTPS 인증서 (카메라 기능에 필요)"
if ! command -v certbot >/dev/null; then
  (apt-get install -y certbot python3-certbot-nginx >/dev/null 2>&1 || yum install -y certbot python3-certbot-nginx >/dev/null 2>&1) || true
fi
if command -v certbot >/dev/null; then
  certbot --nginx -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email --redirect \
    || echo "!! 인증서 발급 실패. http://$DOMAIN 으로는 접속되며, 카메라 대신 사진 업로드를 쓰면 됩니다."
else
  echo "!! certbot 설치 실패. http://$DOMAIN 으로 접속하세요."
fi

echo "완료 → https://$DOMAIN"
