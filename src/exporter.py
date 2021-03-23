from typing import Any, Callable, Dict

from celery import Celery
from prometheus_client import CollectorRegistry

from .constants import TASK_EVENT_LABELS, WORKER_EVENT_LABELS, EventType, LabelName
from .event_handlers import (
    TaskEventHandler,
    TaskStartedEventHandler,
    WorkerHeartbeatEventHandler,
    WorkerStatusEventHandler,
)
from .http_server import start_http_server
from .instrumentation import EventCounter, EventGauge


class Exporter:
    state = None

    def __init__(self):
        self.app = None
        self.registry = CollectorRegistry(auto_describe=True)
        self.state_counters = {
            EventType.TASK_SENT: EventCounter(
                "celery_task_sent",
                "Sent when a task message is published.",
                TASK_EVENT_LABELS,
                registry=self.registry,
            ),
            EventType.TASK_RECEIVED: EventCounter(
                "celery_task_received",
                "Sent when the worker receives a task.",
                TASK_EVENT_LABELS,
                registry=self.registry,
            ),
            EventType.TASK_STARTED: EventCounter(
                "celery_task_started",
                "Sent just before the worker executes the task.",
                TASK_EVENT_LABELS,
                registry=self.registry,
            ),
            EventType.TASK_SUCCEEDED: EventCounter(
                "celery_task_succeeded",
                "Sent if the task executed successfully.",
                TASK_EVENT_LABELS,
                registry=self.registry,
            ),
            EventType.TASK_FAILED: EventCounter(
                "celery_task_failed",
                "Sent if the execution of the task failed.",
                [*TASK_EVENT_LABELS, LabelName.EXCEPTION],
                registry=self.registry,
            ),
            EventType.TASK_REJECTED: EventCounter(
                "celery_task_rejected",
                # pylint: disable=line-too-long
                "The task was rejected by the worker, possibly to be re-queued or moved to a dead letter queue.",
                TASK_EVENT_LABELS,
                registry=self.registry,
            ),
            EventType.TASK_REVOKED: EventCounter(
                "celery_task_revoked",
                "Sent if the task has been revoked.",
                TASK_EVENT_LABELS,
                registry=self.registry,
            ),
            EventType.TASK_RETRIED: EventCounter(
                "celery_task_retried",
                "Sent if the task failed, but will be retried in the future.",
                TASK_EVENT_LABELS,
                registry=self.registry,
            ),
        }
        self.queuing_time_gauge = EventGauge(
            "celery_task_queuing_time_seconds",
            "How long in seconds the task spent waiting in the queue before it started executing.",
            TASK_EVENT_LABELS,
            registry=self.registry,
        )
        self.celery_worker_up = EventGauge(
            "celery_worker_up",
            "Indicates if a worker has recently sent a heartbeat.",
            WORKER_EVENT_LABELS,
            registry=self.registry,
        )
        self.worker_tasks_active = EventGauge(
            "celery_worker_tasks_active",
            "The number of tasks the worker is currently processing",
            WORKER_EVENT_LABELS,
            registry=self.registry,
        )

    def get_handlers(self) -> Dict[str, Callable]:
        handlers = {
            EventType.WORKER_HEARTBEAT: WorkerHeartbeatEventHandler(
                state=self.state,
                worker_up_gauge=self.celery_worker_up,
                worker_tasks_active_gauge=self.worker_tasks_active,
            ),
            EventType.WORKER_ONLINE: WorkerStatusEventHandler(
                state=self.state, is_online=True, worker_up_gauge=self.celery_worker_up
            ),
            EventType.WORKER_OFFLINE: WorkerStatusEventHandler(
                state=self.state, is_online=False, worker_up_gauge=self.celery_worker_up
            ),
        }
        for event_type, counter in self.state_counters.items():
            handlers[event_type] = TaskEventHandler(state=self.state, counter=counter)
        handlers[EventType.TASK_STARTED] = TaskStartedEventHandler(
            state=self.state,
            counter=self.state_counters[EventType.TASK_STARTED],
            queuing_time_gauge=self.queuing_time_gauge,
        )

        return handlers

    def run(self, click_params: Dict[str, Any]):
        self.app = Celery(broker=click_params["broker_url"])
        self.state = self.app.events.State()

        with self.app.connection() as connection:
            start_http_server(self.registry, connection, click_params["port"])
            recv = self.app.events.Receiver(connection, handlers=self.get_handlers())
            recv.capture(limit=None, timeout=None, wakeup=True)
