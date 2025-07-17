docker build -f Dockerfile.pyinstaller . -t cel-ex-builder
docker rm celex -f
docker run --name celex -d cel-ex-builder
rm celery-exporter
docker cp celex:/app/dist/celery-exporter .