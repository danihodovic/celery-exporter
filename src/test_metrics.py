import logging
import time
from datetime import datetime, timezone

import pytest
from celery.contrib.testing.worker import start_worker  # type: ignore
from celery.utils.time import adjust_timestamp, utcoffset  # type: ignore

from src.exporter import Exporter, reverse_adjust_timestamp


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

        
QUEUE_WAIT_TASK_NAME = "src.test_metrics.waiting_task"
QUEUE_WAIT_BASE_TIME = 1_600_000_000.0


def make_task_event(event_type, timestamp, utcoffset=None):
    return {
        "type": event_type,
        "uuid": "7d9b0b6c-6b1e-4c1e-a0f5-000000000001",
        "timestamp": timestamp,
        "local_received": timestamp,
        "hostname": "worker@wait-test-host",
        "clock": 1,
        "utcoffset": utcoffset,
    }


def make_task_sent_event(timestamp, eta=None, retries=0, utcoffset=None):
    event = make_task_event("task-sent", timestamp, utcoffset=utcoffset)
    event.update(name=QUEUE_WAIT_TASK_NAME, queue="celery", eta=eta, retries=retries)
    return event


def isoformat_eta(timestamp):
    return datetime.fromtimestamp(timestamp, tz=timezone.utc).isoformat()


def get_queue_wait_sample(exporter, suffix):
    return exporter.registry.get_sample_value(
        f"celery_task_queue_wait_time_{suffix}",
        labels={
            "name": QUEUE_WAIT_TASK_NAME,
            "hostname": "wait-test-host",
            "queue_name": "celery",
        },
    )


@pytest.mark.parametrize(
    "eta,started_offset,expected_wait",
    [
        pytest.param(None, 5, 5.0, id="plain-task"),
        pytest.param(
            isoformat_eta(QUEUE_WAIT_BASE_TIME + 120),
            123,
            3.0,
            id="future-eta-excluded",
        ),
        pytest.param(
            isoformat_eta(QUEUE_WAIT_BASE_TIME - 60),
            5,
            5.0,
            id="past-eta-ignored",
        ),
        pytest.param(None, -2, 0.0, id="clamped-to-zero-on-clock-skew"),
    ],
)
def test_queue_wait_time(event_exporter, eta, started_offset, expected_wait):
    """A task is sent at the base time (optionally with an ETA) and started
    `started_offset` seconds later; the wait is measured from max(sent, eta)
    and clamped at zero."""
    event_exporter.track_task_event(make_task_sent_event(QUEUE_WAIT_BASE_TIME, eta=eta))
    event_exporter.track_task_event(
        make_task_event("task-started", QUEUE_WAIT_BASE_TIME + started_offset)
    )

    assert get_queue_wait_sample(event_exporter, "count") == 1.0
    assert get_queue_wait_sample(event_exporter, "sum") == pytest.approx(expected_wait)


def test_queue_wait_time_measures_each_retry_delivery_without_backoff(event_exporter):
    # first delivery: waits 1s
    event_exporter.track_task_event(make_task_sent_event(QUEUE_WAIT_BASE_TIME))
    event_exporter.track_task_event(
        make_task_event("task-started", QUEUE_WAIT_BASE_TIME + 1)
    )
    event_exporter.track_task_event(
        make_task_event("task-retried", QUEUE_WAIT_BASE_TIME + 2)
    )
    # retry delivery: republished with a 30s backoff ETA, waits 3s past it
    event_exporter.track_task_event(
        make_task_sent_event(
            QUEUE_WAIT_BASE_TIME + 2,
            eta=isoformat_eta(QUEUE_WAIT_BASE_TIME + 32),
            retries=1,
        )
    )
    event_exporter.track_task_event(
        make_task_event("task-started", QUEUE_WAIT_BASE_TIME + 35)
    )

    # 1s for the first delivery plus 3s for the retry delivery
    assert get_queue_wait_sample(event_exporter, "count") == 2.0
    assert get_queue_wait_sample(event_exporter, "sum") == pytest.approx(4.0)


def test_queue_wait_time_not_observed_when_sent_event_missed(event_exporter):
    event_exporter.track_task_event(
        make_task_event("task-started", QUEUE_WAIT_BASE_TIME)
    )

    assert get_queue_wait_sample(event_exporter, "count") is None


def test_queue_wait_time_buckets_independent_of_runtime_buckets():
    exporter = Exporter(buckets=[1.0, 5.0], queue_wait_buckets=[2.0, 4.0])

    # pylint: disable=protected-access
    assert exporter.celery_task_queue_wait_time._upper_bounds == [
        2.0,
        4.0,
        float("inf"),
    ]
    assert exporter.celery_task_runtime._upper_bounds == [1.0, 5.0, float("inf")]


def test_queue_wait_time_excludes_eta_when_events_from_other_timezone(event_exporter):
    """The event receiver localises event timestamps based on the sender's
    utcoffset, while the ETA stays an absolute datetime. The ETA must be
    localised the same way, or the exclusion silently never applies when the
    producer/worker timezone differs from the exporter's."""
    source_utcoffset = utcoffset() + 4

    def localise(timestamp):
        # what Receiver.event_from_message does to event timestamps
        return adjust_timestamp(timestamp, source_utcoffset)

    event_exporter.track_task_event(
        make_task_sent_event(
            localise(QUEUE_WAIT_BASE_TIME),
            eta=isoformat_eta(QUEUE_WAIT_BASE_TIME + 120),
            utcoffset=source_utcoffset,
        )
    )
    event_exporter.track_task_event(
        make_task_event(
            "task-started",
            localise(QUEUE_WAIT_BASE_TIME + 123),
            utcoffset=source_utcoffset,
        )
    )

    assert get_queue_wait_sample(event_exporter, "count") == 1.0
    assert get_queue_wait_sample(event_exporter, "sum") == pytest.approx(3.0)
