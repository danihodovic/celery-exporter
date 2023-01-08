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

    @celery_app.task
    def fail():
        raise HTTPError("Intentional error")

    # start worker first so the exporter can fetch and cache queue information
    with start_worker(celery_app, without_heartbeat=False):
        time.sleep(5)
        res = requests.get(exporter_url)
        assert res.status_code == 200
        assert 'celery_queue_length{queue_name="celery"} 0.0' in res.text, res.text
        # TODO: This metric exists for RabbitMQ. Fix it once we've fixed the other brokers
        if broker != "rabbitmq":
            assert (
                'celery_active_consumer_count{queue_name="celery"} 0.0' in res.text
            ), res.text

    succeed.apply_async()
    succeed.apply_async()
    fail.apply_async()

    # assert celery_queue_length when message in broker but no worker start
    res = requests.get(exporter_url)
    assert res.status_code == 200
    assert 'celery_queue_length{queue_name="celery"} 3.0' in res.text
    assert 'celery_active_consumer_count{queue_name="celery"} 0.0' in res.text

    # start worker and consume message in broker
    with start_worker(celery_app, without_heartbeat=False):
        time.sleep(2)

    res = requests.get(exporter_url)
    assert res.status_code == 200
    # pylint: disable=line-too-long
    assert (
        f'celery_task_sent_total{{hostname="{hostname}",name="src.test_cli.succeed"}} 2.0'
        in res.text
    )
    assert (
        f'celery_task_sent_total{{hostname="{hostname}",name="src.test_cli.fail"}} 1.0'
        in res.text
    )
    assert (
        f'celery_task_received_total{{hostname="{hostname}",name="src.test_cli.succeed"}} 2.0'
        in res.text
    )
    assert (
        f'celery_task_received_total{{hostname="{hostname}",name="src.test_cli.fail"}} 1.0'
        in res.text
    )
    assert (
        f'celery_task_started_total{{hostname="{hostname}",name="src.test_cli.succeed"}} 2.0'
        in res.text
    )
    assert (
        f'celery_task_started_total{{hostname="{hostname}",name="src.test_cli.fail"}} 1.0'
        in res.text
    )
    assert (
        f'celery_task_succeeded_total{{hostname="{hostname}",name="src.test_cli.succeed"}} 2.0'
        in res.text
    )
    assert (
        f'celery_task_failed_total{{exception="HTTPError",hostname="{hostname}",name="src.test_cli.fail"}} 1.0'
        in res.text
    )
    assert (
        f'celery_task_runtime_count{{hostname="{hostname}",name="src.test_cli.succeed"}} 2.0'
        in res.text
    )
    assert 'celery_queue_length{queue_name="celery"} 0.0' in res.text

    # TODO: This metric exists for RabbitMQ. Fix it once we've fixed the other brokers
    if broker != "rabbitmq":
        assert 'celery_active_consumer_count{queue_name="celery"} 0.0' in res.text
