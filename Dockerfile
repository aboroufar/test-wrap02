# ============================
# 1. BUILDER STAGE
# ============================
#FROM registry.cloud.sky/ndss-broadband/python3.12:latest AS builder
FROM python:3.10-slim AS builder

ARG ROOT_PROJ_DIR=/app

# Install base build packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    git \
    wget \
    unzip \
    ca-certificates \
    gnupg \
    lsb-release \
    ssh \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI (optional)
RUN curl -fsSL https://get.docker.com -o get-docker.sh && \
    sh get-docker.sh && \
    rm get-docker.sh

WORKDIR $ROOT_PROJ_DIR

# Copy dependency files first
COPY pyproject.toml ./


# --- Install dependencies using SSH secret ---
# Note: everything must be in the same RUN command for the secret to be available
RUN --mount=type=secret,id=ssh_private_key \
    mkdir -p -m 0700 /root/.ssh && \
    echo "Host *\n\tStrictHostKeyChecking no\n" > /root/.ssh/config && \
    cp /run/secrets/ssh_private_key /root/.ssh/id_rsa && \
    chmod 600 /root/.ssh/id_rsa && \
    pip install --no-cache-dir poetry && \
    poetry config virtualenvs.create false && \
    poetry install --with wrappers --no-root --no-interaction --no-ansi

# Copy the full source code after dependencies
COPY src src
COPY workers.sh ./
COPY tests tests
COPY .env ./

# ============================
# 2. FINAL STAGE
# ============================
FROM python:3.10-slim AS final

ARG ROOT_PROJ_DIR=/app
ENV ROOT_PROJ_DIR=$ROOT_PROJ_DIR

# Install only minimal runtime packages required for execution
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    bash \
    ssh \
    && rm -rf /var/lib/apt/lists/*

WORKDIR $ROOT_PROJ_DIR

# Copy the built project and installed dependencies from the builder stage
COPY --from=builder $ROOT_PROJ_DIR $ROOT_PROJ_DIR

# Install Poetry and dependencies
RUN --mount=type=secret,id=ssh_private_key \
    mkdir -p -m 0700 /root/.ssh && \
    echo "Host *\n\tStrictHostKeyChecking no\n" > /root/.ssh/config && \
    cp /run/secrets/ssh_private_key /root/.ssh/id_rsa && \
    chmod 600 /root/.ssh/id_rsa && \
    pip install --no-cache-dir poetry && \
    poetry config virtualenvs.create false && \
    poetry install --with wrappers --no-root --no-interaction --no-ansi

# Ensure the workers.sh script is executable
RUN chmod +x ./workers.sh

# Run the workers.sh script as the container's default command
CMD ["bash", "./workers.sh"]
