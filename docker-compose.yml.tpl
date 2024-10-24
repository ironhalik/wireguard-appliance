services:
  proxy:
    image: caddy:2.8-alpine
    restart: unless-stopped
    ports:
      - 80:80/tcp
      - 443:443/tcp
      - 443:443/udp
    command: >
      sh -c "
      echo '{
        email ${wg_email}
      }

      ${wg_host} {
        reverse_proxy server:51821
      }' > /etc/caddy/Caddyfile &&
      exec caddy run --config /etc/caddy/Caddyfile
      "
    volumes:
      - ./data/caddy/data:/data/caddy
      - ./data/caddy/config:/config/caddy
    logging:
      options:
          max-size: "100m"
  server:
    image: ghcr.io/wg-easy/wg-easy:14
    restart: unless-stopped
    ports:
      - 51820:51820/udp
    volumes:
      - ./data/wg-easy:/etc/wireguard
    environment:
      - LANG=en
      - WG_HOST=${wg_host}
      - 'PASSWORD_HASH=${wg_password}'
      - WG_ALLOWED_IPS=${wg_allowed_ips}
      - WG_ENABLE_ONE_TIME_LINKS=true
      - UI_TRAFFIC_STATS=true
      - UI_CHART_TYPE=1
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
    logging:
      options:
          max-size: "100m"
