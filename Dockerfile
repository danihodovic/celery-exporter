FROM python:3.10-slim-bullseye

EXPOSE 9808
ENV PYTHONUNBUFFERED 1
ENV CELERY_ACCEPT_CONTENT "json"

WORKDIR /app/
COPY pyproject.toml poetry.lock /app/
RUN apt-get update && \
    apt-get -y dist-upgrade && \
    apt install -y locales libcurl4-openssl-dev libssl-dev build-essential\
        && apt-get clean \
        && rm -rf /var/lib/apt/lists/* \
    && pip install -U pip poetry \
    && rm -rf /root/.cache \
    && poetry config virtualenvs.create false \
    && poetry install --no-interaction \
    && rm -rf /root/.cache \
    && apt remove -y build-essential

COPY . /app/

ENTRYPOINT python /app/cli.py --accept-content=${CELERY_ACCEPT_CONTENT}
