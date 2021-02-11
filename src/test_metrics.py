import threading
import time

import pytest
from celery.contrib.testing.worker import start_worker


@pytest.mark.celery()
def test_worker_tasks_active(exporter, mocker, celery_app, celery_worker):
    labels = mocker.patch.object(exporter.worker_tasks_active, "labels")
    threading.Thread(target=exporter.run, args=(exporter.cfg,), daemon=True).start()

    @celery_app.task
    def slow_task():
        time.sleep(6)

    celery_worker.reload()
    slow_task.apply_async()
    time.sleep(4)
    labels.assert_called_with(hostname=celery_worker.hostname)
    labels.return_value.set.assert_any_call(1)


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
