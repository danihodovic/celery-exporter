import logging
import time

import pytest
from celery.contrib.testing.worker import start_worker  # type: ignore
from celery.utils.time import adjust_timestamp  # type: ignore

from src.exporter import reverse_adjust_timestamp


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


@pytest.mark.parametrize(
    "input_utcoffset, sleep_seconds, expected_metric_value",
    [
        (None, 5, 0.0),
        (0, 5, 0.0),
        (7, 5, 0.0),
        (7, 0, 1.0),
    ],  # Eg: PST (America/Los_Angeles)
)
def test_worker_timeout_status(
    input_utcoffset, sleep_seconds, expected_metric_value, threaded_exporter, hostname
):
    ts = adjust_timestamp(time.time(), (input_utcoffset or 0))
    threaded_exporter.track_worker_status(
        {"hostname": hostname, "timestamp": ts, "utcoffset": input_utcoffset}, True
    )
    assert (
        threaded_exporter.registry.get_sample_value(
            "celery_worker_up", labels={"hostname": hostname}
        )
        == 1.0
    )
    assert threaded_exporter.worker_last_seen[hostname] == {
        "forgotten": False,
        "ts": reverse_adjust_timestamp(ts, input_utcoffset),
    }

    time.sleep(sleep_seconds)
    threaded_exporter.scrape()
    assert (
        threaded_exporter.registry.get_sample_value(
            "celery_worker_up", labels={"hostname": hostname}
        )
        == expected_metric_value
    )


@pytest.mark.parametrize(
    "input_utcoffset, sleep_seconds, expected_metric_value",
    [
        (None, 15, None),
        (0, 15, None),
        (7, 15, None),
        (7, 0, 1.0),
    ],  # Eg: PST (America/Los_Angeles)
)
def test_purge_offline_worker_metrics(
    input_utcoffset, sleep_seconds, expected_metric_value, threaded_exporter, hostname
):
    ts = adjust_timestamp(time.time(), (input_utcoffset or 0))
    threaded_exporter.track_worker_status(
        {"hostname": hostname, "timestamp": ts, "utcoffset": input_utcoffset}, True
    )
    threaded_exporter.worker_tasks_active.labels(hostname=hostname).inc()
    threaded_exporter.celery_task_runtime.labels(
        name="boosh", hostname=hostname, queue_name="test"
    ).observe(1.0)
    threaded_exporter.state_counters["task-sent"].labels(
        name="boosh", hostname=hostname, queue_name="test"
    ).inc()

    assert (
        threaded_exporter.registry.get_sample_value(
            "celery_worker_up", labels={"hostname": hostname}
        )
        == 1.0
    )
    assert (
        threaded_exporter.registry.get_sample_value(
            "celery_worker_tasks_active", labels={"hostname": hostname}
        )
        == 1.0
    )
    assert (
        threaded_exporter.registry.get_sample_value(
            "celery_task_runtime_count",
            labels={"hostname": hostname, "queue_name": "test", "name": "boosh"},
        )
        == 1.0
    )
    assert (
        threaded_exporter.registry.get_sample_value(
            "celery_task_sent_total",
            labels={"hostname": hostname, "queue_name": "test", "name": "boosh"},
        )
        == 1.0
    )

    assert threaded_exporter.worker_last_seen[hostname] == {
        "forgotten": False,
        "ts": reverse_adjust_timestamp(ts, input_utcoffset),
    }

    time.sleep(sleep_seconds)
    threaded_exporter.scrape()
    assert (
        threaded_exporter.registry.get_sample_value(
            "celery_worker_up", labels={"hostname": hostname}
        )
        == expected_metric_value
    )
    assert (
        threaded_exporter.registry.get_sample_value(
            "celery_worker_tasks_active", labels={"hostname": hostname}
        )
        == expected_metric_value
    )
    assert (
        threaded_exporter.registry.get_sample_value(
            "celery_task_runtime_count",
            labels={"hostname": hostname, "queue_name": "test", "name": "boosh"},
        )
        == expected_metric_value
    )
    assert (
        threaded_exporter.registry.get_sample_value(
            "celery_task_sent_total",
            labels={"hostname": hostname, "queue_name": "test", "name": "boosh"},
        )
        == expected_metric_value
    )


def test_worker_generic_task_sent_hostname(threaded_exporter, celery_app):
    threaded_exporter.generic_hostname_task_sent_metric = True
    time.sleep(5)

    @celery_app.task
    def succeed():
        pass

    succeed.apply_async()

    with start_worker(celery_app, without_heartbeat=False):
        time.sleep(5)
        assert (
            threaded_exporter.registry.get_sample_value(
                "celery_task_sent_total",
                labels={
                    "hostname": "generic",
                    "name": "src.test_metrics.succeed",
                    "queue_name": "celery",
                },
            )
            == 1.0
        )
