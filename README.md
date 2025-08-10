# Hetzner Terraform + Docker + GitHub Actions (Linux → Linux)

Provision a Hetzner Cloud VM with **Terraform**, install **Docker** via cloud‑init, build a tiny Flask app into a Docker image, push to **Docker Hub**, and **deploy over SSH** using **GitHub Actions**.

---

## 🧭 Project Goals

- **Infra**: 1× Ubuntu VM on Hetzner + firewall (allow only 22/80/443)
- **App**: Minimal Flask app in a Docker image
- **CI/CD**: GitHub Actions builds & pushes to Docker Hub, then SSH‑deploys
- **From scratch** on Linux (developer machine + server both Linux)

---

## 📁 Repository Structure

```
hetzner-tf-cicd/
├─ terraform/
│  ├─ versions.tf
│  ├─ variables.tf
│  ├─ main.tf
│  ├─ outputs.tf
│  ├─ cloud-init.yaml
│  └─ terraform.tfvars            # local only (ignored by .gitignore)
├─ app/
│  ├─ app.py
│  └─ Dockerfile
└─ .github/
   └─ workflows/
      └─ ci.yml
```

---

## 🧱 Architecture (high level)

```
Local (Git) ──push──▶ GitHub
                      │
                      ├──▶ Build & Push Image ──▶ Docker Hub
                      │
                      └──▶ SSH Deploy ─────────▶ Hetzner VM (Docker run)
                        ▲
 Terraform ──create─────┘  (VM + firewall + cloud‑init installs Docker)
```

---

## ✅ Prerequisites

- Linux workstation (Debian/Ubuntu examples below)
- GitHub account
- Docker Hub account (for image registry)
- Hetzner Cloud account & **API Token**

Install tools locally (Ubuntu/Debian):
```bash
sudo apt update
sudo apt install -y git openssh-client docker.io gnupg software-properties-common

# Terraform
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform
```

Generate an SSH key (for Hetzner + deploy):
```bash
ssh-keygen -t ed25519 -C "hetzner-deploy" -f ~/.ssh/hetzner_ed25519 -N ""
# public key:  ~/.ssh/hetzner_ed25519.pub  (starts with: ssh-ed25519 ...)
```

Create a **Hetzner Cloud API Token** in your project:  
_Cloud → Security → API Tokens → Generate_.

---

## ⚙️ Terraform Configuration

**`terraform/versions.tf`**
```hcl
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
  }
}
```

**`terraform/variables.tf`**
```hcl
variable "hcloud_token" {
  type      = string
  sensitive = true
}

variable "server_name"  { type = string  default = "mpay-demo-1" }
variable "server_type"  { type = string  default = "cpx11" }
variable "server_location" { type = string default = "hel1" }
variable "image"        { type = string  default = "ubuntu-22.04" }
variable "ssh_public_key_path" { type = string }
```

**`terraform/cloud-init.yaml`**
```yaml
#cloud-config
package_update: true
packages:
  - git
  - docker.io
runcmd:
  - systemctl enable docker
  - systemctl start docker
  - usermod -aG docker root || true
  - ufw disable || true
```

**`terraform/main.tf`**
```hcl
provider "hcloud" {
  token = var.hcloud_token
}

resource "hcloud_ssh_key" "local" {
  name       = "local-key"
  public_key = file(var.ssh_public_key_path)
}

resource "hcloud_firewall" "web_fw" {
  name = "web-allow-22-80-443"

  # inbound
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # outbound (Hetzner requires destination_ips)
  rule {
    direction       = "out"
    protocol        = "icmp"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "1-65535"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "1-65535"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_server" "vm" {
  name         = var.server_name
  server_type  = var.server_type
  image        = var.image
  location     = var.server_location
  ssh_keys     = [hcloud_ssh_key.local.id]
  user_data    = file("${path.module}/cloud-init.yaml")
  firewall_ids = [hcloud_firewall.web_fw.id]
}

output "server_ipv4" {
  value = hcloud_server.vm.ipv4_address
}
```

**`terraform/terraform.tfvars`** (local only; **do not commit**)
```hcl
hcloud_token        = "YOUR_HCLOUD_TOKEN"
ssh_public_key_path = "/home/<you>/.ssh/hetzner_ed25519.pub"  # or /root/.ssh/...
server_name         = "mpay-demo-1"
server_type         = "cpx11"
server_location     = "hel1"
```

Initialize & apply:
```bash
cd terraform
terraform init
terraform apply -auto-approve
# note server_ipv4 from the output
```

Quick SSH check:
```bash
ssh -i ~/.ssh/hetzner_ed25519 root@<server_ipv4> "docker --version"
```

---

## 🧪 App & Docker

**`app/app.py`**
```python
from flask import Flask
app = Flask(__name__)

@app.get("/")
def hello():
    return "Hello from MPay demo on Hetzner via Terraform + GitHub Actions!\n"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
```

**`app/Dockerfile`**
```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY app.py .
RUN pip install --no-cache-dir flask
EXPOSE 8000
CMD ["python", "app.py"]
```

Local test (optional):
```bash
cd app
docker build -t yourdockerhubuser/mpay-demo:local .
docker run -p 8000:8000 yourdockerhubuser/mpay-demo:local
curl localhost:8000
```

---

## 🤖 CI/CD (GitHub Actions)

**`.github/workflows/ci.yml`**
```yaml
name: build-and-deploy

on:
  push:
    branches: [ "main" ]
  workflow_dispatch:

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Login to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: ./app
          push: true
          tags: |
            ${{ secrets.APP_IMAGE }}:latest
            ${{ secrets.APP_IMAGE }}:${{ github.sha }}

  deploy:
    needs: build-and-push
    runs-on: ubuntu-latest
    env:
      HOST: ${{ secrets.SSH_HOST }}
      USER: ${{ secrets.SSH_USER }}
      IMAGE: ${{ secrets.APP_IMAGE }}
    steps:
      - name: Prepare SSH
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.SSH_PRIVATE_KEY }}" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          ssh-keyscan -H "$HOST" >> ~/.ssh/known_hosts

      - name: Deploy on remote server
        run: |
          ssh -i ~/.ssh/id_ed25519 ${USER}@${HOST} << EOF
            set -e
            docker pull ${IMAGE}:latest
            docker rm -f mpay-demo || true
            docker run -d --name mpay-demo --restart unless-stopped               -p 80:8000 ${IMAGE}:latest
          EOF
```
> The workflow **builds** the image from `./app`, **pushes** it to Docker Hub, and **SSH‑deploys** a container that maps container port `8000` to server port `80` (open in the firewall).

### Required GitHub Secrets
Create these in **Repo → Settings → Secrets and variables → Actions**:
- `DOCKERHUB_USERNAME` – your Docker Hub username  
- `DOCKERHUB_TOKEN` – a Docker Hub **Access Token**  
- `APP_IMAGE` – e.g. `yourdockerhubuser/mpay-demo`  
- `SSH_HOST` – public IP from Terraform output (`server_ipv4`)  
- `SSH_USER` – `root` (or another user if you prefer)  
- `SSH_PRIVATE_KEY` – contents of `~/.ssh/hetzner_ed25519` (private key)

Trigger the pipeline:
- Push a commit to `main` **or** run the workflow manually from the **Actions** tab.
- Open `http://<server_ipv4>/` to verify the app is up.

---

## 🚀 Quick Start (from zero)

```bash
# 1) Clone or create the repo and add files (this project)
git init && git add . && git commit -m "Initial: Terraform + app + CI"
git branch -M main
git remote add origin https://github.com/<you>/hetzner-tf-cicd.git
git push -u origin main

# 2) Provision infra
cd terraform
terraform init
terraform apply -auto-approve

# 3) Add GitHub secrets (as above), then push a change or run the workflow

# 4) Visit the app
curl http://<server_ipv4>/
```

---

## 🔐 Security Notes

- Never commit **`terraform.tfvars`**, **private keys**, or **secrets**.
- Rotate tokens/keys periodically.
- Consider creating a non‑root deploy user (limited sudo) and disabling root SSH login.
- For HTTPS/Let’s Encrypt, add a reverse proxy (Caddy/Traefik/Nginx).

---

