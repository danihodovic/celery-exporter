import threading
import time

import pytest
from celery.contrib.testing.worker import start_worker


@pytest.fixture
def assert_exporter_metric_called(mocker, celery_app, celery_worker):
    def fn(exporter, metric):
        labels = mocker.patch.object(metric, "labels")
        threading.Thread(target=exporter.run, args=(exporter.cfg,), daemon=True).start()

        @celery_app.task
        def slow_task():
            time.sleep(6)

        celery_worker.reload()
        slow_task.apply_async()
        time.sleep(4)
        labels.assert_called_with(hostname=celery_worker.hostname)
        labels.return_value.set.assert_any_call(1)

    return fn


@pytest.mark.celery()
def test_worker_tasks_active(exporter, assert_exporter_metric_called):
    assert_exporter_metric_called(exporter, exporter.worker_tasks_active)


@pytest.mark.celery()
def test_worker_heartbeat_status(exporter, assert_exporter_metric_called):
    assert_exporter_metric_called(exporter, exporter.celery_worker_up)


@pytest.mark.celery()
def test_worker_status(exporter, celery_app):
    threading.Thread(target=exporter.run, args=(exporter.cfg,), daemon=True).start()
    time.sleep(5)

    with start_worker(celery_app, without_heartbeat=False) as celery_worker:
        hostname = celery_worker.hostname
        time.sleep(2)
        assert (
            exporter.registry.get_sample_value(
                "celery_worker_up", labels={"hostname": hostname}
            )
            == 1.0
        )

    time.sleep(2)
    assert (
        exporter.registry.get_sample_value(
            "celery_worker_up", labels={"hostname": hostname}
        )
        == 0.0
    )
