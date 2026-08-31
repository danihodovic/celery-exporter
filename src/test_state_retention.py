"""State-retention behavior at the Prometheus scrape boundary."""

# pylint: disable=protected-access

from celery import Celery

from src.exporter import Exporter


def task_event(event_type, task_uuid, clock, **fields):
    timestamp = 1_750_000_000.0 + clock
    return {
        "type": event_type,
        "uuid": task_uuid,
        "hostname": "celery@worker-0",
        "timestamp": timestamp,
        "local_received": timestamp,
        "clock": clock,
        **fields,
    }


def receive_task(exporter, task_uuid, clock, name, queue):
    exporter.track_task_event(
        task_event(
            "task-received",
            task_uuid,
            clock,
            name=name,
            args="[]",
            kwargs="{}",
            retries=0,
            eta=None,
            expires=None,
            queue=queue,
            exchange="",
            routing_key=queue,
        )
    )


def succeed_task(exporter, task_uuid, clock, runtime=0.1):
    exporter.track_task_event(
        task_event(
            "task-succeeded",
            task_uuid,
            clock,
            runtime=runtime,
            result="ok",
        )
    )


def test_scrape_discards_ready_state_but_preserves_active_task_metrics(mocker):
    exporter = Exporter(
        worker_timeout_seconds=0,
        purge_offline_worker_metrics_seconds=0,
    )
    exporter.app = Celery("state-retention-test", broker="memory://")
    exporter.state = exporter.app.events.State()
    mocker.patch.object(exporter, "track_queue_metrics")

    receive_task(exporter, "completed", 1, "profile.completed", "short")
    succeed_task(exporter, "completed", 2)
    receive_task(exporter, "active", 3, "profile.long_running", "reports")
    exporter.track_task_event(task_event("task-started", "active", 4))

    completed_count = exporter.registry.get_sample_value(
        "celery_task_succeeded_total",
        labels={
            "name": "profile.completed",
            "hostname": "worker-0",
            "queue_name": "short",
        },
    )
    assert completed_count == 1.0
    assert set(exporter.state.tasks) == {"completed", "active"}
    assert exporter.state._taskheap

    exporter.scrape()

    assert set(exporter.state.tasks) == {"active"}
    assert exporter.state._taskheap == []
    assert (
        exporter.registry.get_sample_value(
            "celery_task_succeeded_total",
            labels={
                "name": "profile.completed",
                "hostname": "worker-0",
                "queue_name": "short",
            },
        )
        == completed_count
    )

    succeed_task(exporter, "active", 5, runtime=60.0)

    assert (
        exporter.registry.get_sample_value(
            "celery_task_succeeded_total",
            labels={
                "name": "profile.long_running",
                "hostname": "worker-0",
                "queue_name": "reports",
            },
        )
        == 1.0
    )
    assert (
        exporter.registry.get_sample_value(
            "celery_task_runtime_count",
            labels={
                "name": "profile.long_running",
                "hostname": "worker-0",
                "queue_name": "reports",
            },
        )
        == 1.0
    )


def test_terminal_event_survives_concurrent_ready_state_cleanup(mocker):
    exporter = Exporter()
    exporter.app = Celery("state-retention-race-test", broker="memory://")
    exporter.state = exporter.app.events.State()
    receive_task(exporter, "active", 1, "profile.long_running", "reports")

    state_event = exporter.state.event

    def event_then_clear_ready(event):
        result = state_event(event)
        exporter.state.clear_tasks(ready=True)
        return result

    mocker.patch.object(exporter.state, "event", side_effect=event_then_clear_ready)

    succeed_task(exporter, "active", 2, runtime=60.0)

    assert (
        exporter.registry.get_sample_value(
            "celery_task_succeeded_total",
            labels={
                "name": "profile.long_running",
                "hostname": "worker-0",
                "queue_name": "reports",
            },
        )
        == 1.0
    )
