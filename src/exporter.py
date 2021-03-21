# pylint: disable=protected-access,,attribute-defined-outside-init
import re

from celery import Celery
from loguru import logger
from prometheus_client import CollectorRegistry, Counter, Gauge

from .constants import TASK_EVENT_LABELS, WORKER_EVENT_LABELS, LabelName, EventName, EventEnum
from .http_server import start_http_server


class Exporter:
    state = None

    def __init__(self):
        self.registry = CollectorRegistry(auto_describe=True)
        self.state_counters = {
            EventName.TASK_SENT: Counter(
                "celery_task_sent",
                "Sent when a task message is published.",
                TASK_EVENT_LABELS,
                registry=self.registry,
            ),
            EventName.TASK_RECEIVED: Counter(
                "celery_task_received",
                "Sent when the worker receives a task.",
                TASK_EVENT_LABELS,
                registry=self.registry,
            ),
            EventName.TASK_STARTED: Counter(
                "celery_task_started",
                "Sent just before the worker executes the task.",
                TASK_EVENT_LABELS,
                registry=self.registry,
            ),
            EventName.TASK_SUCCEEDED: Counter(
                "celery_task_succeeded",
                "Sent if the task executed successfully.",
                TASK_EVENT_LABELS,
                registry=self.registry,
            ),
            EventName.TASK_FAILED: Counter(
                "celery_task_failed",
                "Sent if the execution of the task failed.",
                [*TASK_EVENT_LABELS, LabelName.EXCEPTION],
                registry=self.registry,
            ),
            EventName.TASK_REJECTED: Counter(
                "celery_task_rejected",
                # pylint: disable=line-too-long
                "The task was rejected by the worker, possibly to be re-queued or moved to a dead letter queue.",
                TASK_EVENT_LABELS,
                registry=self.registry,
            ),
            EventName.TASK_REVOKED: Counter(
                "celery_task_revoked",
                "Sent if the task has been revoked.",
                TASK_EVENT_LABELS,
                registry=self.registry,
            ),
            EventName.TASK_RETRIED: Counter(
                "celery_task_retried",
                "Sent if the task failed, but will be retried in the future.",
                TASK_EVENT_LABELS,
                registry=self.registry,
            ),
        }
        self.task_queuing_time = Gauge(
            "celery_task_queuing_time",
            "How long the task spent waiting in the queue before it started executing.",
            TASK_EVENT_LABELS,
            registry=self.registry,
        )
        self.celery_worker_up = Gauge(
            "celery_worker_up",
            "Indicates if a worker has recently sent a heartbeat.",
            WORKER_EVENT_LABELS,
            registry=self.registry,
        )
        self.worker_tasks_active = Gauge(
            "celery_worker_tasks_active",
            "The number of tasks the worker is currently processing",
            WORKER_EVENT_LABELS,
            registry=self.registry,
        )

    def track_task_event(self, event):
        self.state.event(event)
        task = self.state.tasks.get(event[EventEnum.UUID])
        logger.debug("Received event='{}' for task='{}'", event[EventEnum.TYPE], task.name)

        counter = self.state_counters.get(event[EventEnum.TYPE])
        if not counter:
            logger.warning("No counter matches task state='{}'", task.state)
            return

        labels = {}
        # pylint: disable=protected-access
        for labelname in counter._labelnames:
            value = getattr(task, labelname)
            if labelname == LabelName.EXCEPTION:
                logger.debug(value)
                value = get_exception_class(value)
            labels[labelname] = value
        counter.labels(**labels).inc()

        if event[EventEnum.TYPE] in [EventName.TASK_STARTED, EventName.TASK_FAILED]:
            queue_time = task.started - task.received
            self.task_queuing_time.labels(**labels).set(queue_time)

        logger.debug("Incremented metric='{}' labels='{}'", counter._name, labels)

    def track_worker_status(self, event, is_online):
        value = 1 if is_online else 0
        event_name = EventName.WORKER_ONLINE if is_online else EventName.WORKER_OFFLINE
        hostname = event[EventEnum.HOSTNAME]
        logger.debug("Received event='{}' for hostname='{}'", event_name, hostname)
        self.celery_worker_up.labels(hostname=hostname).set(value)

    def track_worker_heartbeat(self, event):
        logger.debug(
            "Received event='{}' for worker='{}'", event[EventEnum.TYPE], event[EventEnum.HOSTNAME]
        )

        worker_state = self.state.event(event)[0][0]
        active = worker_state.active or 0
        up = 1 if worker_state.alive else 0
        self.celery_worker_up.labels(hostname=event[EventEnum.HOSTNAME]).set(up)
        self.worker_tasks_active.labels(hostname=event[EventEnum.HOSTNAME]).set(active)
        logger.debug(
            "Updated gauge='{}' value='{}'", self.worker_tasks_active._name, active
        )
        logger.debug("Updated gauge='{}' value='{}'", self.celery_worker_up._name, up)

    def run(self, click_params):
        self.app = Celery(broker=click_params["broker_url"])
        self.state = self.app.events.State()

        handlers = {
            EventName.WORKER_HEARTBEAT: self.track_worker_heartbeat,
            EventName.WORKER_ONLINE: lambda event: self.track_worker_status(event, True),
            EventName.WORKER_OFFLINE: lambda event: self.track_worker_status(event, False),
        }
        for key in self.state_counters:
            handlers[key] = self.track_task_event

        with self.app.connection() as connection:
            start_http_server(self.registry, connection, click_params["port"])
            recv = self.app.events.Receiver(connection, handlers=handlers)
            recv.capture(limit=None, timeout=None, wakeup=True)


exception_pattern = re.compile(r"^(\w+)\(")


def get_exception_class(exception_name: str):
    m = exception_pattern.match(exception_name)
    return m.group(1)
