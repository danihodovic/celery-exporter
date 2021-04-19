# pylint: disable=unused-argument
import time
from threading import Thread

import pytest
import requests


@pytest.fixture
def run_exporter(exporter, celery_app):
    Thread(target=exporter.run, args=(exporter.cfg,), daemon=True).start()
    time.sleep(1)
    return exporter


@pytest.mark.celery()
def test_health(run_exporter):
    res = requests.get(f"http://localhost:{run_exporter.cfg['port']}/health")
    res.raise_for_status()


def test_index(run_exporter):
    res = requests.get(f"http://localhost:{run_exporter.cfg['port']}")
    res.raise_for_status()
    assert "/metrics" in res.text
