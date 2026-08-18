import logging
import time
from types import SimpleNamespace

import pytest
from celery.contrib.testing.worker import start_worker  # type: ignore
from celery.utils.time import adjust_timestamp  # type: ignore

from src.exporter import Exporter, reverse_adjust_timestamp


def track_event(exporter, event_type, task):
    exporter.state = SimpleNamespace(
        event=lambda _event: None,
        tasks=SimpleNamespace(get=lambda _uuid: task),
    )
    exporter.track_task_event({"type": event_type, "uuid": "task-id"})


def track_task_sent(exporter, task):
    track_event(exporter, "task-sent", task)


@pytest.fixture
def assert_exporter_metric_called(mocker, celery_app, hostname):
    def fn(metric):
        labels = mocker.patch.object(metric, "labels")

        @celery_app.task
        def slow_task():
            logging.info("Started the slow task")
            time.sleep(3)
            logging.info("Finished the slow task")

        # Use start_worker context manager to ensure worker is available
        with start_worker(celery_app, without_heartbeat=False):
            time.sleep(1)
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


def test_worker_offline_event_does_not_recreate_purged_metric(hostname):
    exporter = Exporter()
    exporter.track_worker_status(
        {"hostname": hostname, "timestamp": time.time(), "utcoffset": 0}, True
    )
    exporter.purge_worker_metrics(hostname)

    assert (
        exporter.registry.get_sample_value(
            "celery_worker_up", labels={"hostname": hostname}
        )
        is None
    )

    exporter.track_worker_status(
        {"hostname": hostname, "timestamp": time.time(), "utcoffset": 0}, False
    )

    assert (
        exporter.registry.get_sample_value(
            "celery_worker_up", labels={"hostname": hostname}
        )
        is None
    )


def test_purge_stale_generic_task_sent_metrics(mocker):
    exporter = Exporter(
        purge_offline_worker_metrics_seconds=10,
        generic_hostname_task_sent_metric=True,
        static_label={"cluster": "test"},
    )
    now = mocker.patch("src.exporter.time.time")

    now.return_value = 100
    track_task_sent(
        exporter,
        SimpleNamespace(name="old-task", hostname="client@one", queue="first"),
    )
    now.return_value = 105
    track_task_sent(
        exporter,
        SimpleNamespace(name="active-task", hostname="client@two", queue="second"),
    )

    now.return_value = 111
    exporter.track_timed_out_workers()

    assert (
        exporter.registry.get_sample_value(
            "celery_task_sent_total",
            labels={
                "hostname": "generic",
                "name": "old-task",
                "queue_name": "first",
                "cluster": "test",
            },
        )
        is None
    )
    assert (
        exporter.registry.get_sample_value(
            "celery_task_sent_total",
            labels={
                "hostname": "generic",
                "name": "active-task",
                "queue_name": "second",
                "cluster": "test",
            },
        )
        == 1.0
    )


def test_generic_task_sent_last_seen_is_refreshed(mocker):
    exporter = Exporter(
        purge_offline_worker_metrics_seconds=10,
        generic_hostname_task_sent_metric=True,
    )
    task = SimpleNamespace(name="active-task", hostname="client@one", queue="celery")
    now = mocker.patch("src.exporter.time.time")

    now.return_value = 100
    track_task_sent(exporter, task)
    now.return_value = 109
    track_task_sent(exporter, task)
    now.return_value = 111
    exporter.track_timed_out_workers()

    assert (
        exporter.registry.get_sample_value(
            "celery_task_sent_total",
            labels={
                "hostname": "generic",
                "name": "active-task",
                "queue_name": "celery",
            },
        )
        == 2.0
    )


def test_generic_task_sent_is_not_tracked_when_purging_is_disabled(mocker):
    exporter = Exporter(
        purge_offline_worker_metrics_seconds=0,
        generic_hostname_task_sent_metric=True,
    )
    mocker.patch("src.exporter.time.time", return_value=100)

    track_task_sent(
        exporter,
        SimpleNamespace(name="task", hostname="client@one", queue="celery"),
    )

    assert not exporter.generic_last_seen
    assert (
        exporter.registry.get_sample_value(
            "celery_task_sent_total",
            labels={"hostname": "generic", "name": "task", "queue_name": "celery"},
        )
        == 1.0
    )


def test_generic_metrics_are_not_tracked_when_flags_are_disabled(mocker):
    exporter = Exporter(purge_offline_worker_metrics_seconds=10)
    mocker.patch("src.exporter.time.time", return_value=100)

    track_task_sent(
        exporter,
        SimpleNamespace(name="task", hostname="client@one", queue="celery"),
    )

    # Real-hostname series are the worker lifecycle's responsibility, so they must not
    # end up on the generic purge timer.
    assert not exporter.generic_last_seen
    assert (
        exporter.registry.get_sample_value(
            "celery_task_sent_total",
            labels={"hostname": "one", "name": "task", "queue_name": "celery"},
        )
        == 1.0
    )


def test_generic_task_sent_metric_is_recreated_after_purge(mocker):
    exporter = Exporter(
        purge_offline_worker_metrics_seconds=10,
        generic_hostname_task_sent_metric=True,
    )
    task = SimpleNamespace(name="task", hostname="client@one", queue="celery")
    labels = {"hostname": "generic", "name": "task", "queue_name": "celery"}
    now = mocker.patch("src.exporter.time.time")

    now.return_value = 100
    track_task_sent(exporter, task)
    now.return_value = 111
    exporter.track_timed_out_workers()

    assert exporter.registry.get_sample_value("celery_task_sent_total", labels) is None

    now.return_value = 112
    track_task_sent(exporter, task)

    # The counter restarts from zero rather than resuming the pre-purge total.
    assert exporter.registry.get_sample_value("celery_task_sent_total", labels) == 1.0

    now.return_value = 123
    exporter.track_timed_out_workers()

    assert exporter.registry.get_sample_value("celery_task_sent_total", labels) is None


def test_purge_stale_generic_worker_task_metrics(mocker):
    exporter = Exporter(
        purge_offline_worker_metrics_seconds=10,
        generic_hostname_worker_task_metric=True,
    )
    labels = {"hostname": "generic", "name": "task", "queue_name": "celery"}
    now = mocker.patch("src.exporter.time.time")

    now.return_value = 100
    track_event(
        exporter,
        "task-succeeded",
        SimpleNamespace(
            name="task", hostname="worker@one", queue="celery", runtime=1.5
        ),
    )

    # The event increments task-succeeded and zero-instantiates every sibling counter,
    # all at hostname="generic". None of them are reachable by worker purging.
    assert (
        exporter.registry.get_sample_value("celery_task_succeeded_total", labels) == 1.0
    )
    assert (
        exporter.registry.get_sample_value("celery_task_started_total", labels) == 0.0
    )
    assert (
        exporter.registry.get_sample_value("celery_task_runtime_count", labels) == 1.0
    )

    now.return_value = 111
    exporter.track_timed_out_workers()

    assert (
        exporter.registry.get_sample_value("celery_task_succeeded_total", labels)
        is None
    )
    assert (
        exporter.registry.get_sample_value("celery_task_started_total", labels) is None
    )
    assert (
        exporter.registry.get_sample_value("celery_task_runtime_count", labels) is None
    )
    assert not exporter.generic_last_seen


def test_purge_stale_generic_worker_task_metrics_with_exception_label(mocker):
    exporter = Exporter(
        purge_offline_worker_metrics_seconds=10,
        generic_hostname_worker_task_metric=True,
    )
    labels = {
        "hostname": "generic",
        "name": "task",
        "queue_name": "celery",
        "exception": "ValueError",
    }
    now = mocker.patch("src.exporter.time.time")

    now.return_value = 100
    track_event(
        exporter,
        "task-failed",
        SimpleNamespace(
            name="task",
            hostname="worker@one",
            queue="celery",
            exception="ValueError('boom')",
        ),
    )

    # task-failed carries an extra label, so purging must key off each metric's own
    # label names rather than a shared labelset.
    assert exporter.registry.get_sample_value("celery_task_failed_total", labels) == 1.0

    now.return_value = 111
    exporter.track_timed_out_workers()

    assert (
        exporter.registry.get_sample_value("celery_task_failed_total", labels) is None
    )
    assert not exporter.generic_last_seen


def test_generic_worker_task_metrics_do_not_purge_real_hostname_series(mocker):
    exporter = Exporter(purge_offline_worker_metrics_seconds=10)
    now = mocker.patch("src.exporter.time.time")

    now.return_value = 100
    track_event(
        exporter,
        "task-succeeded",
        SimpleNamespace(
            name="task", hostname="worker@one", queue="celery", runtime=1.5
        ),
    )

    now.return_value = 111
    exporter.track_timed_out_workers()

    # Without a heartbeat there is no worker_last_seen entry, so worker purging leaves
    # these alone; the generic timer must not reach them either.
    assert (
        exporter.registry.get_sample_value(
            "celery_task_succeeded_total",
            labels={"hostname": "one", "name": "task", "queue_name": "celery"},
        )
        == 1.0
    )


def test_worker_generic_task_sent_hostname(threaded_exporter, celery_app, hostname):
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

        assert (
            threaded_exporter.registry.get_sample_value(
                "celery_task_sent_total",
                labels={
                    "hostname": hostname,
                    "name": "src.test_metrics.succeed",
                    "queue_name": "celery",
                },
            )
            is None
        )


def test_worker_generic_task_hostname(threaded_exporter, celery_app, hostname):
    threaded_exporter.generic_hostname_worker_task_metric = True
    time.sleep(5)

    @celery_app.task
    def succeed():
        pass

    succeed.apply_async()

    with start_worker(celery_app, without_heartbeat=False):
        time.sleep(5)

        # The worker-executed counter and the runtime histogram carry the generic
        # hostname, not the executing worker's.
        assert (
            threaded_exporter.registry.get_sample_value(
                "celery_task_succeeded_total",
                labels={
                    "hostname": "generic",
                    "name": "src.test_metrics.succeed",
                    "queue_name": "celery",
                },
            )
            == 1.0
        )
        assert (
            threaded_exporter.registry.get_sample_value(
                "celery_task_runtime_count",
                labels={
                    "hostname": "generic",
                    "name": "src.test_metrics.succeed",
                    "queue_name": "celery",
                },
            )
            == 1.0
        )
        # The runtime histogram is only ever touched by observe() on the collapsed
        # worker event, so no series exists under the real worker hostname.
        assert (
            threaded_exporter.registry.get_sample_value(
                "celery_task_runtime_count",
                labels={
                    "hostname": hostname,
                    "name": "src.test_metrics.succeed",
                    "queue_name": "celery",
                },
            )
            is None
        )

        # celery_task_sent is client-side and governed by its own flag, so this flag
        # leaves it labeled with the real hostname.
        assert (
            threaded_exporter.registry.get_sample_value(
                "celery_task_sent_total",
                labels={
                    "hostname": hostname,
                    "name": "src.test_metrics.succeed",
                    "queue_name": "celery",
                },
            )
            == 1.0
        )

        # celery_worker_up does not pass through track_task_event, so it keeps the real
        # per-worker hostname that KEDA's scaler depends on.
        assert (
            threaded_exporter.registry.get_sample_value(
                "celery_worker_up", labels={"hostname": hostname}
            )
            == 1.0
        )
        assert (
            threaded_exporter.registry.get_sample_value(
                "celery_worker_up", labels={"hostname": "generic"}
            )
            is None
        )
