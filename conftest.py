import socket
import threading
import time
import copy

import pytest
from celery.events.state import State  # type: ignore

from src.exporter import Exporter


def pytest_addoption(parser):
    parser.addoption(
        "--broker",
        action="store",
        default="redis",
        help="What broker to use in tests",
        choices=("redis", "rabbitmq", "memory"),
    )
    parser.addoption(
        "--loglevel",
        action="store",
        default="INFO",
        help="Log level of the exporter and celery worker in tests",
        choices=("DEBUG", "INFO", "WARNING", "ERROR"),
    )


@pytest.fixture(scope="session")
def broker(request):
    return request.config.getoption("--broker")


@pytest.fixture(scope="session")
def log_level(request):
    return request.config.getoption("--loglevel")


@pytest.fixture(scope="session")
def celery_config(broker):
    config = dict(
        task_send_sent_event=True,
        worker_send_task_events=True,
    )
    if broker == "redis":
        config["broker_url"] = "redis://localhost:6379/"  # type: ignore
    elif broker == "rabbitmq":
        config["broker_url"] = "amqp://guest:guest@localhost:5672"  # type: ignore
        # RabbitMQ >= 4.3 denies transient non-exclusive queues by default (see
        # rabbitmq_requires_exclusive_queues() in src/exporter.py); the test worker's own
        # event/pidbox queues are exactly that.
        config["event_queue_exclusive"] = True  # type: ignore
        config["control_queue_exclusive"] = True  # type: ignore
    elif broker == "memory":
        config["broker_url"] = "memory://localhost/"  # type: ignore

    return config


# https://github.com/celery/celery/pull/6632
@pytest.fixture(scope="session")
def celery_worker_parameters(log_level):
    return dict(
        loglevel=log_level,
        without_heartbeat=False,
    )


@pytest.fixture(scope="session")
def celery_enable_logging(log_level):
    return log_level == "DEBUG"


def _wait_for_port(port, deadline):
    """
    Waits until 127.0.0.1:port accepts connections.

    Exporter.run() starts the HTTP server only after its RabbitMQ >= 4.3 exclusive-queue check
    completes, so this also guarantees a test can't scrape() ahead of that check.
    """
    while True:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                return
        except OSError as ex:
            if time.monotonic() > deadline:
                raise RuntimeError("exporter http server failed to start") from ex
            time.sleep(0.01)


@pytest.fixture(scope="session")
def find_free_port():
    """
    https://gist.github.com/bertjwregeer/0be94ced48383a42e70c3d9fff1f4ad0
    """

    def _find_free_port():
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(("0.0.0.0", 0))
        portnum = s.getsockname()[1]
        s.close()

        return portnum

    return _find_free_port


# Configurations for exporters
@pytest.fixture(scope="session")
def exporter_cfg_defaults(find_free_port, celery_config, log_level):
    cfg = {
        "host": "0.0.0.0",
        "port": find_free_port(),
        "broker_url": celery_config["broker_url"],
        "broker_transport_option": ["visibility_timeout=7200"],
        "broker_ssl_option": [],
        "retry_interval": 5,
        "log_level": log_level,
        "accept_content": None,
        "worker_timeout": 1,
        "purge_offline_worker_metrics": 10,
        "initial_queues": ["queue_from_command_line"],
    }
    yield cfg


@pytest.fixture()
def exporter_instance(exporter_cfg_defaults, find_free_port):
    exporter_cfg = copy.deepcopy(exporter_cfg_defaults)
    exporter_cfg["port"] = find_free_port()
    exporter = Exporter(
        worker_timeout_seconds=exporter_cfg["worker_timeout"],
        purge_offline_worker_metrics_seconds=exporter_cfg[
            "purge_offline_worker_metrics"
        ],
        initial_queues=exporter_cfg["initial_queues"],
    )
    setattr(exporter, "cfg", exporter_cfg)
    yield exporter


@pytest.fixture()
def threaded_exporter(exporter_instance):
    thread = threading.Thread(
        target=exporter_instance.run, args=(exporter_instance.cfg,), daemon=True
    )
    thread.start()
    # Exporter.run() assigns self.app in the thread, so a test that scrape()s
    # immediately would race it
    deadline = time.monotonic() + 10
    while not hasattr(exporter_instance, "app"):
        if time.monotonic() > deadline:
            raise RuntimeError("exporter thread failed to start")
        time.sleep(0.01)
    _wait_for_port(exporter_instance.cfg["port"], deadline)
    yield exporter_instance


# Fixtures for same exporter, but with static labels
@pytest.fixture
def exporter_instance_static_labels(exporter_cfg_defaults, find_free_port):
    exporter_cfg = copy.deepcopy(exporter_cfg_defaults)
    exporter_cfg["port"] = find_free_port()
    exporter_cfg["static_label"] = {
        "test_label_1": "test_value",
        "test_label_2_long_named": "test_value_2_long_named",
    }
    exporter = Exporter(
        worker_timeout_seconds=exporter_cfg["worker_timeout"],
        purge_offline_worker_metrics_seconds=exporter_cfg[
            "purge_offline_worker_metrics"
        ],
        initial_queues=exporter_cfg["initial_queues"],
        static_label=exporter_cfg["static_label"],
    )
    setattr(exporter, "cfg", exporter_cfg)
    yield exporter


@pytest.fixture()
def threaded_exporter_static_labels(exporter_instance_static_labels):
    thread = threading.Thread(
        target=exporter_instance_static_labels.run,
        args=(exporter_instance_static_labels.cfg,),
        daemon=True,
    )
    thread.start()
    # Exporter.run() assigns self.app in the thread, so a test that scrape()s
    # immediately would race it
    deadline = time.monotonic() + 10
    while not hasattr(exporter_instance_static_labels, "app"):
        if time.monotonic() > deadline:
            raise RuntimeError("exporter thread failed to start")
        time.sleep(0.01)
    _wait_for_port(exporter_instance_static_labels.cfg["port"], deadline)
    yield exporter_instance_static_labels


@pytest.fixture()
def hostname():
    return socket.gethostname()


@pytest.fixture()
def event_exporter():
    """An exporter with task state tracking, fed events directly (no worker)."""
    exporter = Exporter()
    exporter.state = State()
    return exporter
