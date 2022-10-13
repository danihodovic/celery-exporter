FROM python:3.10.9-bullseye

EXPOSE 9808

RUN apt-get update && \
    apt-get -y dist-upgrade && \
    apt install -y locales libcurl4-openssl-dev libssl-dev \
        && apt-get clean \
        && rm -rf /var/lib/apt/lists/*

WORKDIR /app/

RUN pip install poetry==1.2.1 \
    && rm -rf /root/.cache
COPY pyproject.toml poetry.lock /app/
RUN poetry config virtualenvs.create false \
    && poetry install --no-interaction \
    && rm -rf /root/.cache

ENV PYTHONUNBUFFERED 1

COPY . /app/

ENTRYPOINT ["python", "/app/cli.py"]
