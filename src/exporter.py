from celery import Celery, states
from celery.events.snapshot import Polaroid
from loguru import logger
from prometheus_client import CollectorRegistry, Counter, start_http_server


class Exporter(Polaroid):
    clear_after = True  # clear after flush (incl, state.event_count).

    def __init__(self, click_params):
        self.click_params = click_params
        self.registry = CollectorRegistry(auto_describe=True)
        app = Celery(
            broker=click_params["broker_url"],
            backend="memory",
        )
        state = app.events.State()
        super().__init__(state, freq=click_params["frequency"])

        self.state_counters = {
            states.PENDING: Counter(
                "task_sent",
                "Sent when a task message is published.",
                [
                    "name",
                    "hostname",
                ],
                registry=self.registry,
            ),
            states.RECEIVED: Counter(
                "task_received",
                "Sent when the worker receives a task.",
                ["name", "hostname"],
                registry=self.registry,
            ),
            states.STARTED: Counter(
                "task_started",
                "Sent just before the worker executes the task.",
                [
                    "name",
                    "hostname",
                ],
                registry=self.registry,
            ),
            states.FAILURE: Counter(
                "task_failed",
                "Sent if the execution of the task failed.",
                ["name", "hostname"],
                registry=self.registry,
            ),
            states.RETRY: Counter(
                "task_retried",
                "Sent if the task failed, but will be retried in the future.",
                ["name", "hostname"],
                registry=self.registry,
            ),
            states.SUCCESS: Counter(
                "task_succeeded",
                "Sent if the task executed successfully.",
                ["name", "hostname"],
                registry=self.registry,
            ),
            states.REVOKED: Counter(
                "task_revoked",
                "Sent if the task has been revoked.",
                ["name", "hostname"],
                registry=self.registry,
            ),
            states.REJECTED: Counter(
                "task_rejected",
                # pylint: disable=line-too-long
                "The task was rejected by the worker, possibly to be re-queued or moved to a dead letter queue.",
                ["name", "hostname"],
                registry=self.registry,
            ),
        }

    def _measure(self, task):
        logger.debug("Received task with state='{}'", task.state)
        counter = self.state_counters.get(task.state)
        if not counter:
            logger.warning("No counter matches task state='{}'", task.state)
            return

        labels = {}
        # pylint: disable=protected-access
        for labelname in counter._labelnames:
            labels[labelname] = getattr(task, labelname)
        counter.labels(**labels).inc()
        logger.debug("Incremented metric='{}' labels='{}'", counter._name, labels)

    def on_shutter(self, state):
        if not state.event_count:
            logger.debug("No new events since last snapshot")
            return

        for task in state.tasks.values():
            self._measure(task)

    def run(self):
        start_http_server(self.click_params["port"], registry=self.registry)

        with self.app.connection() as connection:
            recv = self.app.events.Receiver(
                connection, handlers={"*": self.state.event}
            )
            with self:
                recv.capture(limit=None, timeout=None)
