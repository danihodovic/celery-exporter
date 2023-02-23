import logging
import time

import pytest
from celery.contrib.testing.worker import start_worker  # type: ignore


@pytest.fixture
def assert_exporter_metric_called(mocker, celery_app, celery_worker, hostname):
    def fn(metric):
        labels = mocker.patch.object(metric, "labels")

        @celery_app.task
        def slow_task():
            logging.info("Started the slow task")
            time.sleep(3)
            logging.info("Finished the slow task")

        # Reload so that the worker detects the task
        celery_worker.reload()
        slow_task.delay().get()
        assert labels.call_count >= 1
        labels.assert_called_with(hostname=hostname)
        labels.return_value.set.assert_any_call(1)

    return fn


@pytest.mark.celery()
def test_worker_tasks_active(broker, threaded_exporter, assert_exporter_metric_called):
    if broker != "memory":
        pytest.skip(
            reason="test_worker_tasks_active can only be tested for the in-memory broker"
        )

    assert_exporter_metric_called(threaded_exporter.worker_tasks_active)


@pytest.mark.celery()
def test_worker_heartbeat_status(
    broker, threaded_exporter, assert_exporter_metric_called
):
    if broker != "memory":
        pytest.skip(
            reason="test_worker_tasks_active can only be tested for the in-memory broker"
        )

    assert_exporter_metric_called(threaded_exporter.celery_worker_up)


@pytest.mark.celery()
def test_worker_status(threaded_exporter, celery_app, hostname):
    time.sleep(5)

    with start_worker(celery_app, without_heartbeat=False):
        time.sleep(2)
        assert (
            threaded_exporter.registry.get_sample_value(
                "celery_worker_up", labels={"hostname": hostname}
            )
            == 1.0
        )

    time.sleep(2)
    assert (
        threaded_exporter.registry.get_sample_value(
            "celery_worker_up", labels={"hostname": hostname}
        )
        == 0.0
    )


@pytest.mark.celery()
def test_worker_heartbeat(threaded_exporter, celery_app, hostname):
    before_start = time.time()
    def get_heartbeat_sample():
        return threaded_exporter.registry.get_sample_value(
            "celery_worker_last_heartbeat_timestamp", labels={"hostname": hostname}
        )
    with start_worker(celery_app, without_heartbeat=False, heartbeat_interval=0.5):
        time.sleep(2)
        heartbeat_sample = get_heartbeat_sample()
        assert heartbeat_sample is not None
        assert heartbeat_sample > before_start
        assert heartbeat_sample < time.time()

    post_shutdown_heartbeat_sample = get_heartbeat_sample()
    time.sleep(10)
    post_sleep_heartbeat_sample = get_heartbeat_sample()
    assert post_shutdown_heartbeat_sample == post_sleep_heartbeat_sample
