import pytest
from celery import states
from celery.events import state  # pylint: disable=no-name-in-module

Task = state.Task


@pytest.mark.parametrize(
    "metric_name,state",
    [
        ("task_sent", states.PENDING),
        ("task_received", states.RECEIVED),
        ("task_started", states.STARTED),
        ("task_failed", states.FAILURE),
        ("task_succeeded", states.SUCCESS),
        ("task_revoked", states.REVOKED),
        ("task_rejected", states.REJECTED),
    ],
)
def test_metric(metric_name, state, exporter):
    t = Task(name="taskname", hostname="machine", state=state)
    # pylint: disable=protected-access
    exporter._measure(t)
    assert (
        exporter.registry.get_sample_value(
            metric_name + "_total", labels={"name": "taskname", "hostname": "machine"}
        )
        == 1.0
    )
