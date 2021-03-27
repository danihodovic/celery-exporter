from typing import Any, Callable, Dict

from celery import Celery

from .constants import EventType
from .event_handlers import (
    TaskEventHandler,
    TaskStartedEventHandler,
    WorkerHeartbeatEventHandler,
    WorkerStatusEventHandler,
)
from .http_server import start_http_server
from .instrumentation import (
    celery_worker_up_gauge,
    queuing_time_gauge,
    registry,
    task_failed_event_counter,
    task_received_event_counter,
    task_rejected_event_counter,
    task_retried_event_counter,
    task_revoked_event_counter,
    task_sent_event_counter,
    task_started_event_counter,
    task_succeeded_event_counter,
    worker_tasks_active_gauge,
)


class Exporter:
    state = None

    def __init__(self):
        self.app = None

    def get_handlers(self) -> Dict[str, Callable]:
        return {
            EventType.TASK_SENT: TaskEventHandler(
                state=self.state, counter=task_sent_event_counter
            ),
            EventType.TASK_RECEIVED: TaskEventHandler(
                state=self.state, counter=task_received_event_counter
            ),
            EventType.TASK_STARTED: TaskStartedEventHandler(
                state=self.state,
                counter=task_started_event_counter,
                queuing_time_gauge=queuing_time_gauge,
            ),
            EventType.TASK_SUCCEEDED: TaskEventHandler(
                state=self.state, counter=task_succeeded_event_counter
            ),
            EventType.TASK_FAILED: TaskEventHandler(
                state=self.state, counter=task_failed_event_counter
            ),
            EventType.TASK_REJECTED: TaskEventHandler(
                state=self.state, counter=task_rejected_event_counter
            ),
            EventType.TASK_REVOKED: TaskEventHandler(
                state=self.state, counter=task_revoked_event_counter
            ),
            EventType.TASK_RETRIED: TaskEventHandler(
                state=self.state, counter=task_retried_event_counter
            ),
            EventType.WORKER_HEARTBEAT: WorkerHeartbeatEventHandler(
                state=self.state,
                worker_up_gauge=celery_worker_up_gauge,
                worker_tasks_active_gauge=worker_tasks_active_gauge,
            ),
            EventType.WORKER_ONLINE: WorkerStatusEventHandler(
                state=self.state, is_online=True, worker_up_gauge=celery_worker_up_gauge
            ),
            EventType.WORKER_OFFLINE: WorkerStatusEventHandler(
                state=self.state,
                is_online=False,
                worker_up_gauge=celery_worker_up_gauge,
            ),
        }

    def run(self, click_params: Dict[str, Any]):
        self.app = Celery(broker=click_params["broker_url"])
        self.state = self.app.events.State()

        with self.app.connection() as connection:
            start_http_server(registry, connection, click_params["port"])
            recv = self.app.events.Receiver(connection, handlers=self.get_handlers())
            recv.capture(limit=None, timeout=None, wakeup=True)
