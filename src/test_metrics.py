import threading
import time

import pytest
from celery.contrib.testing.worker import start_worker  # type: ignore


@pytest.fixture
def assert_exporter_metric_called(mocker, celery_app, celery_worker, hostname):
    def fn(exporter, metric):
        labels = mocker.patch.object(metric, "labels")
        threading.Thread(target=exporter.run, args=(exporter.cfg,), daemon=True).start()

        @celery_app.task
        def slow_task():
            time.sleep(6)

        celery_worker.reload()
        slow_task.apply_async()
        time.sleep(4)
        assert labels.call_count == 3
        labels.assert_called_with(hostname=hostname)
        labels.return_value.set.assert_any_call(1)

    return fn


@pytest.mark.celery()
def test_worker_tasks_active(exporter, assert_exporter_metric_called):
    assert_exporter_metric_called(exporter, exporter.worker_tasks_active)


@pytest.mark.celery()
def test_worker_heartbeat_status(exporter, assert_exporter_metric_called):
    assert_exporter_metric_called(exporter, exporter.celery_worker_up)


@pytest.mark.celery()
def test_worker_status(exporter, celery_app, hostname):
    threading.Thread(target=exporter.run, args=(exporter.cfg,), daemon=True).start()
    time.sleep(5)

    with start_worker(celery_app, without_heartbeat=False):
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


@pytest.mark.celery()
def test_offline_worker_prune_metrics(exporter, celery_app, celery_worker, hostname):

    config = {
        **exporter.cfg,
        **{
            "prune_offline_workers_metrics": True,
        },
    }

    threading.Thread(target=exporter.run, args=(config,), daemon=True).start()
    time.sleep(5)

    with start_worker(celery_app, without_heartbeat=False):
        time.sleep(2)
        assert (
            exporter.registry.get_sample_value(
                "celery_worker_up", labels={"hostname": hostname}
            )
            == 1.0
        )

        @celery_app.task
        def slow_task():
            time.sleep(1)

        celery_worker.reload()
        slow_task.apply_async()
        time.sleep(5)

        assert (
            exporter.registry.get_sample_value(
                "celery_task_sent_total",
                labels={"hostname": hostname, "name": "src.test_metrics.slow_task"},
            )
            == 1.0
        )

    time.sleep(10)
    assert (
        exporter.registry.get_sample_value(
            "celery_worker_up", labels={"hostname": hostname}
        )
        == None
    )
    assert (
        exporter.registry.get_sample_value(
            "celery_task_sent_total",
            labels={"hostname": hostname, "name": "src.test_metrics.slow_task"},
        )
        == None
    )
