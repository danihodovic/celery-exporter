# pylint: disable=unused-argument
import time

import kombu.exceptions
import pytest
import requests
from prometheus_client import CollectorRegistry

from .http_server import create_app


class FakeConnection:
    """Mimics a kombu connection that still holds on to a socket.

    ensure_connection() is a no-op for such a connection even when the
    broker is gone - only connecting anew tells us anything.
    """

    def __init__(self, clone_error=None):
        self.clone_error = clone_error

    def as_uri(self):
        return "redis://localhost:6379//"

    def ensure_connection(self, **kwargs):
        pass

    def clone(self):
        if self.clone_error:
            raise self.clone_error
        return self

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass


def make_client(metrics_puller, connection=None):
    app = create_app(
        CollectorRegistry(auto_describe=True),
        connection or FakeConnection(),
        metrics_puller,
    )
    return app.test_client()


def test_health_fails_when_the_broker_is_unreachable():
    error = kombu.exceptions.OperationalError("No route to host")
    client = make_client(lambda: None, FakeConnection(clone_error=error))

    assert client.get("/health").status_code == 500


def test_metrics_failure_makes_the_exporter_unhealthy():
    def puller():
        raise ConnectionError("Error while reading from redis:6379")

    client = make_client(puller)

    assert client.get("/metrics").status_code == 500
    assert client.get("/health").status_code == 500


def test_health_recovers_once_metrics_can_be_scraped_again():
    scrapes = []

    def puller():
        scrapes.append(1)
        if len(scrapes) == 1:
            raise ConnectionError("Error while reading from redis:6379")

    client = make_client(puller)

    assert client.get("/metrics").status_code == 500
    assert client.get("/health").status_code == 200
    assert client.get("/metrics").status_code == 200


@pytest.mark.celery()
def test_health(threaded_exporter):
    time.sleep(1)
    res = requests.get(
        f"http://localhost:{threaded_exporter.cfg['port']}/health", timeout=3
    )
    res.raise_for_status()


def test_index(threaded_exporter):
    time.sleep(1)
    res = requests.get(f"http://localhost:{threaded_exporter.cfg['port']}", timeout=3)
    res.raise_for_status()
    assert "/metrics" in res.text
