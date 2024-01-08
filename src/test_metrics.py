import logging
import time
from unittest.mock import ANY

import pytest
from celery.contrib.testing.worker import start_worker  # type: ignore

from conftest import timeout_task, failing_task


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


def test_worker_timeout_status(threaded_exporter, hostname):
    ts = time.time()
    threaded_exporter.track_worker_status({"hostname": hostname, "timestamp": ts}, True)
    assert (
        threaded_exporter.registry.get_sample_value(
            "celery_worker_up", labels={"hostname": hostname}
        )
        == 1.0
    )
    assert threaded_exporter.worker_last_seen[hostname] == {
        "forgotten": False,
        "ts": ts,
    }

    time.sleep(5)
    threaded_exporter.scrape()
    assert (
        threaded_exporter.registry.get_sample_value(
            "celery_worker_up", labels={"hostname": hostname}
        )
        == 0.0
    )


def test_purge_offline_worker_metrics(threaded_exporter, hostname):
    ts = time.time()
    threaded_exporter.track_worker_status({"hostname": hostname, "timestamp": ts}, True)
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
        "ts": ts,
    }

    time.sleep(15)
    threaded_exporter.scrape()
    assert (
        threaded_exporter.registry.get_sample_value(
            "celery_worker_up", labels={"hostname": hostname}
        )
        is None
    )
    assert (
        threaded_exporter.registry.get_sample_value(
            "celery_worker_tasks_active", labels={"hostname": hostname}
        )
        is None
    )
    assert (
        threaded_exporter.registry.get_sample_value(
            "celery_task_runtime_count",
            labels={"hostname": hostname, "queue_name": "test", "name": "boosh"},
        )
        is None
    )
    assert (
        threaded_exporter.registry.get_sample_value(
            "celery_task_sent_total",
            labels={"hostname": hostname, "queue_name": "test", "name": "boosh"},
        )
        is None
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


@pytest.mark.celery
def test_time_in_queue(threaded_exporter, celery_app):
    with start_worker(celery_app, perform_ping_check=False):
        timeout_task.delay().get(timeout=10)

        # this is necessary otherwise asserts do not match expectation
        time.sleep(2)

        tasks_in_queue = threaded_exporter.registry.get_sample_value(
            "celery_time_in_queue_count", labels={"queue_name": "celery"}
        )
        time_in_queue_sum = threaded_exporter.registry.get_sample_value(
            "celery_time_in_queue_sum", labels={"queue_name": "celery"}
        )

        assert tasks_in_queue == 1
        assert 0 < time_in_queue_sum < 1.0


@pytest.mark.celery
def test_time_in_queue_ignores_eta(threaded_exporter, celery_app):
    with start_worker(celery_app, perform_ping_check=False):
        timeout_task.apply_async(countdown=0).get(timeout=10)

        # this is necessary otherwise asserts do not match expectation
        time.sleep(2)

        tasks_started = threaded_exporter.registry.get_sample_value(
            "celery_task_started_total", labels=ANY
        )
        assert tasks_started == 1
        assert "celery_time_in_queue_count" not in threaded_exporter.registry.collect()


@pytest.mark.celery
def test_time_in_queue_retries(threaded_exporter, celery_app):
    with start_worker(celery_app, perform_ping_check=False):
        failing_task.delay(fail_n_times=3, countdown=0.1).get(timeout=10)

        # this is necessary otherwise asserts do not match expectation
        time.sleep(2)

        tasks_started = threaded_exporter.registry.get_sample_value(
            "celery_task_started_total", labels=ANY
        )
        tasks_trough_queue = threaded_exporter.registry.get_sample_value(
            "celery_time_in_queue_count", labels={"queue_name": "celery"}
        )

        # Only the first execution goes through the queue, the rest is executed with ETA
        # with event task-retried
        assert tasks_started == 1
        assert tasks_trough_queue == 1


@pytest.mark.celery
def test_time_in_queue_expires(threaded_exporter, celery_app):
    with start_worker(celery_app, perform_ping_check=False):
        result = timeout_task.delay(3)
        timeout_task.apply_async(expires=1)
        result.get(timeout=10)

        # this is necessary otherwise asserts do not match expectation
        time.sleep(2)
        threaded_exporter.scrape()

        tasks_started = threaded_exporter.registry.get_sample_value(
            "celery_task_received_total", labels=ANY
        )
        tasks_trough_queue = threaded_exporter.registry.get_sample_value(
            "celery_time_in_queue_count", labels={"queue_name": "celery"}
        )
        assert tasks_started == 1
        assert tasks_trough_queue == 2


@pytest.mark.xfail(
    reason="Sometimes the task is started before the revoke command is processed"
)
@pytest.mark.celery
def test_time_in_queue_revoke(threaded_exporter, celery_app):
    with start_worker(celery_app, perform_ping_check=False):
        first_result = timeout_task.delay(5)
        revoked_result = timeout_task.delay()
        revoked_result.revoke(terminate=True)
        first_result.get(timeout=10)

        # this is necessary otherwise asserts do not match expectation
        time.sleep(5)
        threaded_exporter.scrape()

        tasks_started = threaded_exporter.registry.get_sample_value(
            "celery_task_started_total", labels=ANY
        )
        tasks_trough_queue = threaded_exporter.registry.get_sample_value(
            "celery_time_in_queue_count", labels={"queue_name": "celery"}
        )
        # Only the first task gets started,
        # the second is revoked before being picked-up by the worker
        assert tasks_started == 1
        assert tasks_trough_queue == 2
