# pylint: disable=unused-argument
import time

import pytest
import requests


@pytest.mark.celery()
def test_health(threaded_exporter):
    time.sleep(1)
    res = requests.get(
        f"http://localhost:{threaded_exporter.cfg['port']}/health", timeout=3
    )
    res.raise_for_status()


@pytest.mark.celery()
def test_health_auth_missing(threaded_exporter_auth):
    time.sleep(1)
    res = requests.get(
        f"http://localhost:{threaded_exporter_auth.cfg['port']}/health", timeout=3
    )
    assert res.status_code == 401


@pytest.mark.celery()
def test_health_auth_present(threaded_exporter_auth):
    time.sleep(1)
    username = threaded_exporter_auth.cfg["http_username"]
    password = threaded_exporter_auth.cfg["http_password"]
    res = requests.get(
        f"http://{username}:{password}@localhost:{threaded_exporter_auth.cfg['port']}/health",
        timeout=3,
    )
    res.raise_for_status()


def test_index(threaded_exporter):
    time.sleep(1)
    res = requests.get(f"http://localhost:{threaded_exporter.cfg['port']}", timeout=3)
    res.raise_for_status()
    assert "/metrics" in res.text
