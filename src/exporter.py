# pylint: disable=protected-access,,attribute-defined-outside-init
import re

from celery import Celery
from loguru import logger
from prometheus_client import CollectorRegistry, Counter, Gauge

from .http_server import start_http_server


class Exporter:
    state = None

    def __init__(self):
        self.registry = CollectorRegistry(auto_describe=True)
        self.state_counters = {
            "task-sent": Counter(
                "celery_task_sent",
                "Sent when a task message is published.",
                [
                    "name",
                    "hostname",
                ],
                registry=self.registry,
            ),
            "task-received": Counter(
                "celery_task_received",
                "Sent when the worker receives a task.",
                ["name", "hostname"],
                registry=self.registry,
            ),
            "task-started": Counter(
                "celery_task_started",
                "Sent just before the worker executes the task.",
                [
                    "name",
                    "hostname",
                ],
                registry=self.registry,
            ),
            "task-succeeded": Counter(
                "celery_task_succeeded",
                "Sent if the task executed successfully.",
                ["name", "hostname"],
                registry=self.registry,
            ),
            "task-failed": Counter(
                "celery_task_failed",
                "Sent if the execution of the task failed.",
                ["name", "hostname", "exception"],
                registry=self.registry,
            ),
            "task-rejected": Counter(
                "celery_task_rejected",
                # pylint: disable=line-too-long
                "The task was rejected by the worker, possibly to be re-queued or moved to a dead letter queue.",
                ["name", "hostname"],
                registry=self.registry,
            ),
            "task-revoked": Counter(
                "celery_task_revoked",
                "Sent if the task has been revoked.",
                ["name", "hostname"],
                registry=self.registry,
            ),
            "task-retried": Counter(
                "celery_task_retried",
                "Sent if the task failed, but will be retried in the future.",
                ["name", "hostname"],
                registry=self.registry,
            ),
        }
        self.celery_worker_up = Gauge(
            "celery_worker_up",
            "Indicates if a worker has recently sent a heartbeat.",
            ["hostname"],
            registry=self.registry,
        )
        self.worker_tasks_active = Gauge(
            "celery_worker_tasks_active",
            "The number of tasks the worker is currently processing",
            ["hostname"],
            registry=self.registry,
        )

    def track_task_event(self, event):
        self.state.event(event)
        task = self.state.tasks.get(event["uuid"])
        logger.debug("Received event='{}' for task='{}'", event["type"], task.name)

        counter = self.state_counters.get(event["type"])
        if not counter:
            logger.warning("No counter matches task state='{}'", task.state)
            return

        labels = {}
        # pylint: disable=protected-access
        for labelname in counter._labelnames:
            value = getattr(task, labelname)
            if labelname == "exception":
                logger.debug(value)
                value = get_exception_class(value)
            labels[labelname] = value
        counter.labels(**labels).inc()
        logger.debug("Incremented metric='{}' labels='{}'", counter._name, labels)

    def track_worker_status(self, event, is_online):
        value = 1 if is_online else 0
        event_name = "worker-online" if is_online else "worker-offline"
        hostname = event["hostname"]
        logger.debug("Received event='{}' for hostname='{}'", event_name, hostname)
        self.celery_worker_up.labels(hostname=hostname).set(value)

    def track_worker_heartbeat(self, event):
        logger.debug(
            "Received event='{}' for worker='{}'", event["type"], event["hostname"]
        )

        worker_state = self.state.event(event)[0][0]
        active = worker_state.active or 0
        up = 1 if worker_state.alive else 0
        self.celery_worker_up.labels(hostname=event["hostname"]).set(up)
        self.worker_tasks_active.labels(hostname=event["hostname"]).set(active)
        logger.debug(
            "Updated gauge='{}' value='{}'", self.worker_tasks_active._name, active
        )
        logger.debug("Updated gauge='{}' value='{}'", self.celery_worker_up._name, up)

    def run(self, click_params):
        self.app = Celery(broker=click_params["broker_url"])
        self.state = self.app.events.State()

        handlers = {
            "worker-heartbeat": self.track_worker_heartbeat,
            "worker-online": lambda event: self.track_worker_status(event, True),
            "worker-offline": lambda event: self.track_worker_status(event, False),
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
