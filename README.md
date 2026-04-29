# Deploy AISIX → `aisix.ruk.solutions` (Docker Compose + Nginx + Cloudflare)

ไฟล์ใน folder นี้:

```
aisix-deploy/
├── docker-compose.yml        # AISIX + etcd
├── config.yaml               # AISIX config (อ้าง etcd ภายใน, admin key)
├── .env.example              # ตัวอย่าง env
└── nginx/
    └── aisix.ruk.solutions.conf
```

ภาพรวม (Cloudflare **Flexible** SSL):

```
Client ──HTTPS──► Cloudflare ──HTTP (port 80)──► VPS:80 (Nginx) ──► 127.0.0.1:3000 / 3001 (AISIX containers)
                                                                            │
                                                                            └── etcd (internal docker network)
```

> Flexible mode = Cloudflare ถือ TLS ฝั่ง client ส่วน CF→origin วิ่งเป็น HTTP
> ปกติ origin จึงไม่ต้องมี cert. ถ้าต่อไปอยากอัปเป็น Full(strict) แค่ออก
> Origin Certificate จาก Cloudflare แล้วเพิ่ม `listen 443 ssl` กลับเข้าไป

---

## 1. เตรียม VPS

ติดตั้ง docker / docker compose v2 / nginx:

```bash
# Ubuntu
curl -fsSL https://get.docker.com | sh
sudo apt-get install -y nginx
```

---

## 2. วางไฟล์ + ตั้ง admin key

```bash
sudo mkdir -p /opt/aisix
sudo cp -r aisix-deploy/* /opt/aisix/
cd /opt/aisix

# สร้าง admin key สุ่ม แล้วใส่ลง config.yaml
ADMIN_KEY=$(openssl rand -hex 16)
sed -i "s/CHANGE_ME_ADMIN_KEY/${ADMIN_KEY}/" config.yaml
echo "ADMIN_KEY=${ADMIN_KEY}"   # ← จำไว้ ใช้คุย Admin API
```

---

## 3. Start AISIX

```bash
cd /opt/aisix
docker compose pull
docker compose up -d
docker compose ps
```

> **⚠️ เรื่อง image tag** — `aisix` ไม่ publish tag `:latest` (ดู
> `.github/workflows/docker.yaml` ของ repo) ที่ใช้ได้คือ:
>
> | tag | ความหมาย |
> | --- | --- |
> | `:dev` | build ล่าสุดของ branch `main` (default ใน compose นี้) |
> | `:vX.Y.Z` | release semver — เช่น `:v0.1.0` |
> | `:X.Y` | minor — เช่น `:0.1` |
>
> ถ้าเจอ `Head "https://ghcr.io/v2/api7/aisix/manifests/latest": unauthorized`
> แปลว่ายังตั้ง tag เป็น `:latest` อยู่ — แก้โดยตั้ง env:
>
> ```bash
> echo "AISIX_IMAGE=ghcr.io/api7/aisix:dev" >> /opt/aisix/.env
> docker compose up -d
> ```

### 3.1 (ทางเลือก) Build เองจาก source

ถ้าอยาก pin commit ตัวเอง / ไม่อยากผูกกับ `:dev`:

```bash
cd /opt/aisix
git clone --depth 1 https://github.com/api7/aisix.git aisix-src
# uncomment block build: ใน docker-compose.yml
# แล้ว set image tag เป็น local
echo "AISIX_IMAGE=aisix:local" >> .env
docker compose build aisix
docker compose up -d
```

ตรวจ:

```bash
curl -s http://127.0.0.1:3001/openapi | head -c 200
# ควรได้ JSON OpenAPI spec
```

---

## 4. Cloudflare DNS + SSL (Flexible)

ที่ Cloudflare dashboard ของโดเมน `ruk.solutions`:

1. **DNS → Add record**
   - Type: `A`
   - Name: `aisix`
   - IPv4: `<public IP ของ VPS>`
   - Proxy status: **Proxied** (เมฆส้ม)
2. **SSL/TLS → Overview → Encryption mode**: เลือก **Flexible**
   (Cloudflare จะคุย HTTPS กับ client แล้วต่อ HTTP เข้า origin)
3. **SSL/TLS → Edge Certificates** เปิด:
   - **Always Use HTTPS** = On (บังคับ client ต้องใช้ https)
   - **Automatic HTTPS Rewrites** = On
4. (แนะนำ) **Network → Allow only Cloudflare IPs**: เปิด firewall ของ VPS ให้
   port 80 รับเฉพาะ IP ของ Cloudflare ตามรายการ https://www.cloudflare.com/ips/

> ⚠️ ข้อควรรู้ของ Flexible: ทราฟฟิกระหว่าง CF↔origin เป็น HTTP ดังนั้น **อย่า
> เปิด port 80 ของ VPS ให้ทั้งโลกเข้าถึง** ปิด IP อื่นด้วย ufw/iptables/cloud
> firewall เหลือแค่ CIDR ของ Cloudflare

---

## 5. ติดตั้ง Nginx config

```bash
sudo cp nginx/aisix.ruk.solutions.conf /etc/nginx/sites-available/
sudo ln -sf /etc/nginx/sites-available/aisix.ruk.solutions.conf \
            /etc/nginx/sites-enabled/aisix.ruk.solutions.conf
sudo nginx -t && sudo systemctl reload nginx
```

> ในไฟล์ config มี `allow ...; deny all;` คอมเมนต์ไว้สำหรับ `/aisix/admin/`,
> `/ui/`, `/openapi` — เปิดใช้งานพร้อมระบุ IP บ้าน/ออฟฟิศก่อน เพราะ admin
> endpoint **ไม่ควรเปิดสาธารณะ**

ตรวจ (ผ่าน Cloudflare):

```bash
curl -I https://aisix.ruk.solutions/healthz
# HTTP/2 200
# server: cloudflare
```

หรือยิงตรง origin ด้วย HTTP (ต้องอยู่ใน VPS หรือ IP ของ Cloudflare):

```bash
curl -H "Host: aisix.ruk.solutions" http://127.0.0.1/healthz
# ok
```

---

## 6. ตั้ง model + api key (Admin API)

ใช้ `ADMIN_KEY` ที่สร้างไว้ใน step 2:

```bash
export ADMIN_KEY=<your-admin-key>
export AISIX=https://aisix.ruk.solutions       # หรือ http://127.0.0.1:3001 ถ้ายิงจาก VPS

# 6.1 ลงทะเบียน OpenAI model
curl -X POST $AISIX/aisix/admin/models \
  -H "Authorization: Bearer $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "gpt4",
    "model": "openai/gpt-4o-mini",
    "provider_config": { "api_key": "sk-..." }
  }'

# 6.2 ลงทะเบียน Anthropic
curl -X POST $AISIX/aisix/admin/models \
  -H "Authorization: Bearer $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "claude",
    "model": "anthropic/claude-3-5-sonnet-20241022",
    "provider_config": { "api_key": "sk-ant-..." }
  }'

# 6.3 ออก API key สำหรับ client
curl -X POST $AISIX/aisix/admin/apikeys \
  -H "Authorization: Bearer $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "ruk-prod-001",
    "allowed_models": ["gpt4", "claude"],
    "rate_limits": { "rpm": 60, "tpm": 100000 }
  }'
```

---

## 7. ตัวอย่างใช้งาน

### 7.1 curl (chat completion)

```bash
curl https://aisix.ruk.solutions/v1/chat/completions \
  -H "Authorization: Bearer ruk-prod-001" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt4",
    "messages": [
      {"role": "system", "content": "ตอบเป็นภาษาไทยสั้น ๆ"},
      {"role": "user",   "content": "ทำไมท้องฟ้าเป็นสีฟ้า?"}
    ]
  }'
```

### 7.2 Streaming (SSE)

```bash
curl -N https://aisix.ruk.solutions/v1/chat/completions \
  -H "Authorization: Bearer ruk-prod-001" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude",
    "stream": true,
    "messages": [{"role":"user","content":"นับ 1 ถึง 10"}]
  }'
```

### 7.3 Python (OpenAI SDK)

```python
from openai import OpenAI

client = OpenAI(
    base_url="https://aisix.ruk.solutions/v1",
    api_key="ruk-prod-001",
)

resp = client.chat.completions.create(
    model="gpt4",                       # ชื่อ model ที่ลงทะเบียนใน AISIX
    messages=[{"role": "user", "content": "สวัสดี"}],
)
print(resp.choices[0].message.content)
```

### 7.4 Node.js (OpenAI SDK)

```js
import OpenAI from "openai";

const client = new OpenAI({
  baseURL: "https://aisix.ruk.solutions/v1",
  apiKey:  "ruk-prod-001",
});

const r = await client.chat.completions.create({
  model: "claude",
  messages: [{ role: "user", content: "hello" }],
});
console.log(r.choices[0].message.content);
```

### 7.5 Embeddings (OpenAI / Gemini)

```bash
curl https://aisix.ruk.solutions/v1/embeddings \
  -H "Authorization: Bearer ruk-prod-001" \
  -H "Content-Type: application/json" \
  -d '{ "model": "gpt4", "input": "AISIX is a Rust LLM gateway." }'
```

---

## 8. Operations

```bash
# ดู log
docker compose -f /opt/aisix/docker-compose.yml logs -f aisix

# upgrade
docker compose -f /opt/aisix/docker-compose.yml pull
docker compose -f /opt/aisix/docker-compose.yml up -d

# stop
docker compose -f /opt/aisix/docker-compose.yml down
```

backup ของ etcd อยู่ใน docker volume `aisix-deploy_etcd-data` — snapshot ด้วย:

```bash
docker exec aisix-etcd etcdctl snapshot save /var/lib/etcd/snapshot.db
docker cp aisix-etcd:/var/lib/etcd/snapshot.db ./etcd-$(date +%F).db
```

---

## 9. Checklist ก่อน production

- [ ] เปลี่ยน `CHANGE_ME_ADMIN_KEY` ใน `config.yaml` แล้ว
- [ ] Cloudflare DNS proxied (เมฆส้ม) + SSL mode = **Flexible**
- [ ] เปิด **Always Use HTTPS** + **Automatic HTTPS Rewrites** ที่ Cloudflare
- [ ] Firewall VPS เปิด port 80 เฉพาะ CIDR ของ Cloudflare (อย่าเปิดทั้งโลก)
- [ ] เปิด `allow … ; deny all;` สำหรับ `/aisix/admin/`, `/ui/`, `/openapi` แล้ว
- [ ] ตั้ง rate limit ที่ระดับ api key (rpm / tpm) ไม่ปล่อย unlimited
- [ ] เปิด Cloudflare WAF rule กัน `/aisix/admin*` จาก country นอก TH (optional)
- [ ] ตั้ง backup etcd snapshot อัตโนมัติ
- [ ] เมื่อพร้อม: อัปเป็น **Full (strict)** + ออก Origin Certificate (เพิ่ม
      `listen 443 ssl` ใน nginx)
