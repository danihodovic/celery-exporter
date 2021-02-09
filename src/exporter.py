import re

from celery import Celery
from loguru import logger
from prometheus_client import CollectorRegistry, Counter, start_http_server


class Exporter:
    state = None

    def __init__(self):
        self.registry = CollectorRegistry(auto_describe=True)
        self.state_counters = {
            "task-sent": Counter(
                "task_sent",
                "Sent when a task message is published.",
                [
                    "name",
                    "hostname",
                ],
                registry=self.registry,
            ),
            "task-received": Counter(
                "task_received",
                "Sent when the worker receives a task.",
                ["name", "hostname"],
                registry=self.registry,
            ),
            "task-started": Counter(
                "task_started",
                "Sent just before the worker executes the task.",
                [
                    "name",
                    "hostname",
                ],
                registry=self.registry,
            ),
            "task-succeeded": Counter(
                "task_succeeded",
                "Sent if the task executed successfully.",
                ["name", "hostname"],
                registry=self.registry,
            ),
            "task-failed": Counter(
                "task_failed",
                "Sent if the execution of the task failed.",
                ["name", "hostname", "exception"],
                registry=self.registry,
            ),
            "task-rejected": Counter(
                "task_rejected",
                # pylint: disable=line-too-long
                "The task was rejected by the worker, possibly to be re-queued or moved to a dead letter queue.",
                ["name", "hostname"],
                registry=self.registry,
            ),
            "task-revoked": Counter(
                "task_revoked",
                "Sent if the task has been revoked.",
                ["name", "hostname"],
                registry=self.registry,
            ),
            "task-retried": Counter(
                "task_retried",
                "Sent if the task failed, but will be retried in the future.",
                ["name", "hostname"],
                registry=self.registry,
            ),
        }

    def track_event(self, event):
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

    @classmethod
    def run(cls, click_params):
        app = Celery(broker=click_params["broker_url"])
        logger.info("Starting celery-exporter at port='{}'", click_params["port"])
        exporter = cls()
        exporter.state = app.events.State()
        start_http_server(click_params["port"], registry=exporter.registry)

        handlers = {}
        for key in exporter.state_counters:
            handlers[key] = exporter.track_event

        with app.connection() as connection:
            recv = app.events.Receiver(connection, handlers=handlers)
            recv.capture(limit=None, timeout=None, wakeup=True)


exception_pattern = re.compile(r"^(\w+)\(")


def get_exception_class(exception_name: str):
    m = exception_pattern.match(exception_name)
    return m.group(1)
