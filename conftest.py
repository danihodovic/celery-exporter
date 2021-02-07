import pytest

from src.exporter import Exporter


@pytest.fixture(scope="session")
def celery_config():
    return {
        "broker_url": "memory://localhost/",
        "worker_send_task_events": True,
        "task_send_sent_event": True,
    }


@pytest.fixture()
def exporter(celery_config):
    return Exporter(
        {
            "broker_url": celery_config["broker_url"],
            "port": 17000,
        }
    )
