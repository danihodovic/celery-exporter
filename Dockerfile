# Stage 1: Build
FROM python:3.13-slim-bookworm AS builder

ENV PYTHONUNBUFFERED=1 \
    POETRY_NO_INTERACTION=1 \
    POETRY_VIRTUALENVS_IN_PROJECT=1 \
    POETRY_VIRTUALENVS_CREATE=1 \
    POETRY_CACHE_DIR=/tmp/poetry_cache

WORKDIR /app/
COPY pyproject.toml poetry.lock /app/
RUN apt-get update && \
    apt-get -y dist-upgrade && \
    apt install -y locales libcurl4-openssl-dev libssl-dev build-essential && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    pip install -U pip poetry && \
    poetry install --without dev --no-root && \
    rm -rf $POETRY_CACHE_DIR

# Stage 2: Runtime environment
FROM python:3.13-slim-bookworm

ENV PYTHONUNBUFFERED=1 \
    VIRTUAL_ENV=/app/.venv \
    PATH="/app/.venv/bin:$PATH"

COPY --from=builder ${VIRTUAL_ENV} ${VIRTUAL_ENV}
COPY . /app/

EXPOSE 9808

RUN adduser --disabled-login exporter

USER exporter

ENTRYPOINT ["python", "/app/cli.py"]
