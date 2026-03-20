import time

from .exporter import Exporter, transform_option_value


def test_transform_option_value():
    test_cases = [
        {"input": "1423", "expected": 1423},
        {"input": '{"password": "pass"}', "expected": {"password": "pass"}},
        {
            "input": '{invalid_json: "value"}',
            "expected": '{invalid_json: "value"}',
        },
        {"input": "my_master", "expected": "my_master"},
    ]

    for case in test_cases:
        assert transform_option_value(case["input"]) == case["expected"]


def _make_task_event(uuid, event_type, timestamp, hostname="worker@host",
                     name="dummy_task", queue="default"):
    """Helper to create a valid Celery task event with required fields."""
    return {
        "uuid": uuid,
        "type": event_type,
        "timestamp": timestamp,
        "local_received": timestamp,
        "clock": 0,
        "hostname": hostname,
        "name": name,
        "queue": queue,
    }


def test_queue_latency_metric():
    """Test that queue latency is measured between task-sent and task-received."""
    from celery import Celery

    app = Celery(broker="memory://")
    exporter = Exporter()
    exporter.app = app
    exporter.state = app.events.State()

    sent_ts = time.time()
    exporter.track_task_event(
        _make_task_event("test-ql-123", "task-sent", sent_ts)
    )
    exporter.track_task_event(
        _make_task_event("test-ql-123", "task-received", sent_ts + 5.0)
    )

    sample_value = exporter.registry.get_sample_value(
        "celery_task_queue_latency_sum",
        labels={"name": "dummy_task", "queue_name": "default"},
    )
    assert sample_value is not None
    assert sample_value >= 4.9


def test_queue_latency_negative_skipped():
    """Test that negative queue latency (clock skew) is discarded."""
    from celery import Celery

    app = Celery(broker="memory://")
    exporter = Exporter()
    exporter.app = app
    exporter.state = app.events.State()

    sent_ts = time.time()
    exporter.track_task_event(
        _make_task_event("test-neg-latency", "task-sent", sent_ts)
    )
    # received_ts is before sent_ts (clock skew)
    exporter.track_task_event(
        _make_task_event("test-neg-latency", "task-received", sent_ts - 1.0)
    )

    sample_value = exporter.registry.get_sample_value(
        "celery_task_queue_latency_sum",
        labels={"name": "dummy_task", "queue_name": "default"},
    )
    assert sample_value is None or sample_value == 0.0


def test_queue_latency_without_sent_event():
    """Test that queue latency is gracefully skipped when task-sent was not emitted."""
    from celery import Celery

    app = Celery(broker="memory://")
    exporter = Exporter()
    exporter.app = app
    exporter.state = app.events.State()

    # Only send task-received without prior task-sent
    exporter.track_task_event(
        _make_task_event("test-no-sent", "task-received", time.time())
    )

    sample_value = exporter.registry.get_sample_value(
        "celery_task_queue_latency_sum",
        labels={"name": "dummy_task", "queue_name": "default"},
    )
    assert sample_value is None or sample_value == 0.0
