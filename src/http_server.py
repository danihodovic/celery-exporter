from threading import Lock, Thread

import kombu.exceptions
from flask import Blueprint, Flask, current_app, request
from loguru import logger
from prometheus_client.exposition import choose_encoder
from waitress import serve

blueprint = Blueprint("celery_exporter", __name__)


class ScrapeStatus:
    """Keeps track of whether the last metrics scrape succeeded.

    The connections used to collect metrics can break on their own, for
    example after a broker failover. When that happens /metrics fails while
    the broker itself is perfectly reachable, so /health has to look at the
    scrape result as well to notice that the exporter is no longer useful.
    """

    def __init__(self):
        self._lock = Lock()
        self._error = None

    def record_success(self):
        with self._lock:
            self._error = None

    def record_failure(self, error):
        with self._lock:
            self._error = error

    @property
    def error(self):
        with self._lock:
            return self._error


@blueprint.route("/")
def index():
    return """
<!doctype html>
<html lang="en">
  <head>
    <!-- Required meta tags -->
    <meta charset="utf-8">
    <title>celery-exporter</title>
  </head>
  <body>
    <h1>Celery Exporter</h1>
    <p><a href="/metrics">Metrics</a></p>
  </body>
</html>
"""


@blueprint.route("/metrics")
def metrics():
    try:
        current_app.config["metrics_puller"]()
    except Exception as ex:  # pylint: disable=broad-except
        current_app.config["scrape_status"].record_failure(ex)
        logger.exception("Failed to scrape metrics")
        return (f"Failed to scrape metrics: {ex}", 500)

    current_app.config["scrape_status"].record_success()
    encoder, content_type = choose_encoder(request.headers.get("accept"))
    output = encoder(current_app.config["registry"])
    return output, 200, {"Content-Type": content_type}


@blueprint.route("/health")
def health():
    conn = current_app.config["celery_connection"]
    uri = conn.as_uri()

    try:
        # ensure_connection() returns immediately while kombu holds a socket
        # for the connection, even when that socket is dead. Probing on a
        # fresh connection forces an actual round-trip to the broker.
        with conn.clone() as probe:
            probe.ensure_connection(max_retries=3)
    except kombu.exceptions.OperationalError:
        logger.error("Failed to connect to broker='{}'", uri)
        return (f"Failed to connect to broker: '{uri}'", 500)
    except Exception:  # pylint: disable=broad-except
        logger.exception("Unrecognized error")
        return ("Unknown exception", 500)

    # A reachable broker isn't enough - the exporter is only healthy if it can
    # also serve metrics. Rerun the scrape rather than reporting the stored
    # failure, so that a single failed scrape doesn't keep the exporter
    # unhealthy until the next time Prometheus comes around.
    if current_app.config["scrape_status"].error is not None:
        try:
            current_app.config["metrics_puller"]()
        except Exception as ex:  # pylint: disable=broad-except
            current_app.config["scrape_status"].record_failure(ex)
            logger.error("Connected to broker='{}' but unable to scrape: {}", uri, ex)
            return (f"Connected to the broker {uri}, but unable to scrape: {ex}", 500)
        current_app.config["scrape_status"].record_success()

    return f"Connected to the broker {uri}"


def create_app(registry, celery_connection, metrics_puller):
    app = Flask(__name__)
    app.config["registry"] = registry
    app.config["celery_connection"] = celery_connection
    app.config["metrics_puller"] = metrics_puller
    app.config["scrape_status"] = ScrapeStatus()
    app.register_blueprint(blueprint)
    return app


def start_http_server(registry, celery_connection, host, port, metrics_puller):
    app = create_app(registry, celery_connection, metrics_puller)
    Thread(
        target=serve,
        args=(app,),
        kwargs=dict(host=host, port=port, _quiet=True),
        daemon=True,
    ).start()
    logger.info("Started celery-exporter at host='{}' on port='{}'", host, port)
