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


def test_index(threaded_exporter):
    time.sleep(1)
    res = requests.get(f"http://localhost:{threaded_exporter.cfg['port']}", timeout=3)
    res.raise_for_status()
    assert "/metrics" in res.text
