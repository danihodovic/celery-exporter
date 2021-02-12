import pytest

from src.exporter import Exporter


@pytest.fixture(scope="session")
def celery_config():
    return {
        "broker_url": "memory://localhost/",
        "worker_send_task_events": True,
        "task_send_sent_event": True,
    }


# https://github.com/celery/celery/pull/6632
@pytest.fixture(scope="session")
def celery_worker_parameters():
    return {"without_heartbeat": False}


@pytest.fixture()
def exporter(celery_config):
    return Exporter(
        {
            "broker_url": celery_config["broker_url"],
            "port": 17000,
        }
    )


@pytest.fixture(scope="session")
def find_free_port():
    """
    https://gist.github.com/bertjwregeer/0be94ced48383a42e70c3d9fff1f4ad0
    """

    def _find_free_port():
        import socket

        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(("0.0.0.0", 0))
        portnum = s.getsockname()[1]
        s.close()

        return portnum

    return _find_free_port


@pytest.fixture()
def exporter(find_free_port, celery_config):
    cfg = {"port": find_free_port(), "broker_url": celery_config["broker_url"]}
    exporter = Exporter()
    setattr(exporter, "cfg", cfg)
    yield exporter
