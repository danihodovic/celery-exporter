from prometheus_client import Counter, Gauge, CollectorRegistry

from src.constants import TASK_EVENT_LABELS, LabelName, WORKER_EVENT_LABELS

registry = CollectorRegistry(auto_describe=True)


class EventInstrumentMixin:
    @property
    def labelnames(self):
        return self._labelnames

    @property
    def name(self):
        return self._name

    @property
    def documentation(self):
        return self._documentation


class EventCounter(Counter, EventInstrumentMixin):
    pass


class EventGauge(Gauge, EventInstrumentMixin):
    pass


task_sent_event_counter = EventCounter(
    "celery_task_sent",
    "Sent when a task message is published.",
    TASK_EVENT_LABELS,
    registry=registry,
)

task_received_event_counter = EventCounter(
    "celery_task_received",
    "Sent when the worker receives a task.",
    TASK_EVENT_LABELS,
    registry=registry,
)

task_started_event_counter = EventCounter(
    "celery_task_started",
    "Sent just before the worker executes the task.",
    TASK_EVENT_LABELS,
    registry=registry,
)

task_succeeded_event_counter = EventCounter(
    "celery_task_succeeded",
    "Sent if the task executed successfully.",
    TASK_EVENT_LABELS,
    registry=registry,
)

task_failed_event_counter = EventCounter(
    "celery_task_failed",
    "Sent if the execution of the task failed.",
    [*TASK_EVENT_LABELS, LabelName.EXCEPTION],
    registry=registry,
)

task_rejected_event_counter = EventCounter(
    "celery_task_rejected",
    # pylint: disable=line-too-long
    "The task was rejected by the worker, possibly to be re-queued or moved to a dead letter queue.",
    TASK_EVENT_LABELS,
    registry=registry,
)

task_revoked_event_counter = EventCounter(
    "celery_task_revoked",
    "Sent if the task has been revoked.",
    TASK_EVENT_LABELS,
    registry=registry,
)

task_retried_event_counter = EventCounter(
    "celery_task_retried",
    "Sent if the task failed, but will be retried in the future.",
    TASK_EVENT_LABELS,
    registry=registry,
)

queuing_time_gauge = EventGauge(
    "celery_task_queuing_time_seconds",
    "How long in seconds the task spent waiting in the queue before it started executing.",
    TASK_EVENT_LABELS,
    registry=registry,
)

celery_worker_up_gauge = EventGauge(
    "celery_worker_up",
    "Indicates if a worker has recently sent a heartbeat.",
    WORKER_EVENT_LABELS,
    registry=registry,
)

worker_tasks_active_gauge = EventGauge(
    "celery_worker_tasks_active",
    "The number of tasks the worker is currently processing",
    WORKER_EVENT_LABELS,
    registry=registry,
)

ALL_INSTRUMENTS = [
    task_sent_event_counter,
    task_received_event_counter,
    task_started_event_counter,
    task_succeeded_event_counter,
    task_failed_event_counter,
    task_rejected_event_counter,
    task_revoked_event_counter,
    task_retried_event_counter,
    queuing_time_gauge,
    celery_worker_up_gauge,
    worker_tasks_active_gauge,
]
