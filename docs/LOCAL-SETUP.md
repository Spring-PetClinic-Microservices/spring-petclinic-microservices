# Local Setup Guide — Spring Petclinic Microservices (Ubuntu 22.04)

## Prerequisites

- Ubuntu 22.04
- Docker
- Java 17
- Maven Wrapper (`./mvnw`)

Project repository:
https://github.com/spring-petclinic/spring-petclinic-microservices

---

# 1. System Setup (Java, Docker, Git, Tools)

## 1.1 Update Ubuntu

```bash
sudo apt update && sudo apt upgrade -y
```

---

## 1.2 Install Java 17

```bash
sudo apt install -y openjdk-17-jdk
```

Verify:

```bash
java -version
```

Expected:

```text
openjdk version "17"
```

---

## 1.3 Install Docker, You skip if you have docker running and goto step # 2. Enter Project Directory

### Remove old Docker versions

```bash
sudo apt remove docker docker-engine docker.io containerd runc
```

### Install dependencies

```bash
sudo apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
```

### Add Docker GPG key

```bash
sudo mkdir -p /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
```

### Add Docker repository

```bash
echo \
  "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

### Install Docker Engine

```bash
sudo apt update

sudo apt install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
```

### Start Docker

```bash
sudo systemctl enable docker
sudo systemctl start docker
```

### Run Docker without sudo

```bash
sudo usermod -aG docker $USER
newgrp docker
```

Verify:

```bash
docker --version
docker compose version
```

---

# 2. Enter Project Directory

```bash

cd spring-petclinic-microservices
```

---

# 3. Fix Maven Wrapper (Windows Line Endings Issue)

```bash
sudo apt install -y dos2unix

dos2unix mvnw
chmod +x mvnw
```

Verify Maven:

```bash
./mvnw -version
```

---

# 4. Build Docker Images

```bash
./mvnw clean install -P buildDocker -DskipTests
```

---

# 5. Start System

```bash
docker compose up
```

---
# 6. Stop System

```bash
docker compose down
```

---
# 7. Login to ECR (required once per session)

```bash
aws ecr get-login-password --region us-east-1 \
| docker login --username AWS --password-stdin ecr_repository_url
```

# 8. Tag your existing images for ECR

```bash
docker tag <service_name>:latest:latest 123456789012.dkr.ecr.us-east-1.amazonaws.com/<service_name>:latest
```

---
---
# 9. Push images to ECR

```bash
docker push ecr_repository_url/<service_name>:latest
```

---
# Done 🎉
