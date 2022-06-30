import threading
import time

import pytest
import requests
from celery.contrib.testing.worker import start_worker  # type: ignore
from click.testing import CliRunner
from requests.exceptions import HTTPError

from .cli import cli


@pytest.mark.celery()
def test_integration(celery_app):
    def run():
        CliRunner().invoke(
            cli,
            [
                "--broker-url=memory://localhost",
                "--port=23000",
                "--broker-transport-option",
                "visibility_timeout=7200",
                "--retry-interval=5",
            ],
        )

    threading.Thread(target=run, daemon=True).start()
    time.sleep(2)

    @celery_app.task
    def succeed():
        pass

    @celery_app.task
    def fail():
        raise HTTPError("Big, big error")

    # start worker first so the exporter can fetch and cache queue information
    with start_worker(celery_app, without_heartbeat=False) as celery_worker:
        res = requests.get("http://localhost:23000/metrics")
        assert res.status_code == 200
        assert 'celery_queue_length{queue_name="celery"} 0.0' in res.text
        assert 'celery_active_consumer_count{queue_name="celery"} 0.0' in res.text

    succeed.apply_async()
    succeed.apply_async()
    fail.apply_async()

    # assert celery_queue_length when message in broker but no worker start
    res = requests.get("http://localhost:23000/metrics")
    assert res.status_code == 200
    assert 'celery_queue_length{queue_name="celery"} 3.0' in res.text
    assert 'celery_active_consumer_count{queue_name="celery"} 0.0' in res.text

    # start worker and consume message in broker
    with start_worker(celery_app, without_heartbeat=False) as celery_worker:
        time.sleep(2)

    res = requests.get("http://localhost:23000/metrics")
    assert res.status_code == 200
    # pylint: disable=line-too-long
    assert (
        f'celery_task_sent_total{{hostname="{celery_worker.hostname}",name="src.test_cli.succeed"}} 2.0'
        in res.text
    )
    assert (
        f'celery_task_sent_total{{hostname="{celery_worker.hostname}",name="src.test_cli.fail"}} 1.0'
        in res.text
    )
    assert (
        f'celery_task_received_total{{hostname="{celery_worker.hostname}",name="src.test_cli.succeed"}} 2.0'
        in res.text
    )
    assert (
        f'celery_task_received_total{{hostname="{celery_worker.hostname}",name="src.test_cli.fail"}} 1.0'
        in res.text
    )
    assert (
        f'celery_task_started_total{{hostname="{celery_worker.hostname}",name="src.test_cli.succeed"}} 2.0'
        in res.text
    )
    assert (
        f'celery_task_started_total{{hostname="{celery_worker.hostname}",name="src.test_cli.fail"}} 1.0'
        in res.text
    )
    assert (
        f'celery_task_succeeded_total{{hostname="{celery_worker.hostname}",name="src.test_cli.succeed"}} 2.0'
        in res.text
    )
    assert (
        f'celery_task_failed_total{{exception="HTTPError",hostname="{celery_worker.hostname}",name="src.test_cli.fail"}} 1.0'
        in res.text
    )
    assert (
        f'celery_task_runtime_count{{hostname="{celery_worker.hostname}",name="src.test_cli.succeed"}} 2.0'
        in res.text
    )
    assert 'celery_queue_length{queue_name="celery"} 0.0' in res.text
    assert 'celery_active_consumer_count{queue_name="celery"} 0.0' in res.text
