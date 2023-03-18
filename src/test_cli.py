import time

import pytest
import requests
from celery.contrib.testing.worker import start_worker  # type: ignore
from requests.exceptions import HTTPError


@pytest.mark.celery()
def test_integration(broker, celery_app, threaded_exporter, hostname):
    exporter_url = f"http://localhost:{threaded_exporter.cfg['port']}/metrics"

    @celery_app.task
    def succeed():
        pass

    @celery_app.task(priority=4)
    def succeed_p4():
        pass

    @celery_app.task
    def fail():
        raise HTTPError("Intentional error")

    # start worker first so the exporter can fetch and cache queue information
    with start_worker(celery_app, without_heartbeat=False):
        time.sleep(5)
        res = requests.get(exporter_url, timeout=3)
        assert res.status_code == 200
        assert 'celery_queue_length{queue_name="celery"} 0.0' in res.text, res.text
        # TODO: Fix this...
        if broker == "memory":
            assert (
                'celery_active_consumer_count{queue_name="celery"} 0.0' in res.text
            ), res.text

    succeed.apply_async()
    succeed.apply_async()
    succeed_p4.apply_async()
    fail.apply_async()

    # assert celery_queue_length when message in broker but no worker start
    res = requests.get(exporter_url, timeout=3)
    assert res.status_code == 200
    assert 'celery_queue_length{queue_name="celery"} 3.0' in res.text
    assert 'celery_queue_length{queue_name="celery:4"} 1.0' in res.text
    if broker == "memory":
        assert 'celery_active_consumer_count{queue_name="celery"} 0.0' in res.text

    # start worker and consume message in broker
    with start_worker(celery_app, without_heartbeat=False):
        time.sleep(2)

    res = requests.get(exporter_url, timeout=3)
    assert res.status_code == 200
    # pylint: disable=line-too-long
    assert (
        f'celery_task_sent_total{{hostname="{hostname}",name="src.test_cli.succeed",queue_name="celery"}} 2.0'
        in res.text
    )
    assert (
            f'celery_task_sent_total{{hostname="{hostname}",name="src.test_cli.succeed_p4",queue_name="celery"}} 1.0'
            in res.text
    )
    assert (
        f'celery_task_sent_total{{hostname="{hostname}",name="src.test_cli.fail",queue_name="celery"}} 1.0'
        in res.text
    )
    assert (
        f'celery_task_received_total{{hostname="{hostname}",name="src.test_cli.succeed",queue_name="celery"}} 2.0'
        in res.text
    )
    assert (
        f'celery_task_received_total{{hostname="{hostname}",name="src.test_cli.fail",queue_name="celery"}} 1.0'
        in res.text
    )
    assert (
        f'celery_task_started_total{{hostname="{hostname}",name="src.test_cli.succeed",queue_name="celery"}} 2.0'
        in res.text
    )
    assert (
        f'celery_task_started_total{{hostname="{hostname}",name="src.test_cli.fail",queue_name="celery"}} 1.0'
        in res.text
    )
    assert (
        f'celery_task_succeeded_total{{hostname="{hostname}",name="src.test_cli.succeed",queue_name="celery"}} 2.0'
        in res.text
    )
    assert (
        f'celery_task_failed_total{{exception="HTTPError",hostname="{hostname}",name="src.test_cli.fail",queue_name="celery"}} 1.0'
        in res.text
    )
    assert (
        f'celery_task_runtime_count{{hostname="{hostname}",name="src.test_cli.succeed",queue_name="celery"}} 2.0'
        in res.text
    )
    assert 'celery_queue_length{queue_name="celery"} 0.0' in res.text
    assert 'celery_queue_length{queue_name="celery:4"} 0.0' in res.text

    # TODO: Fix this...
    if broker == "memory":
        assert 'celery_active_consumer_count{queue_name="celery"} 0.0' in res.text
