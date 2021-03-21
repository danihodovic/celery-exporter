# pylint: disable=too-few-public-methods

from abc import ABC, abstractmethod
from typing import Any, Dict, Union

from celery import Task
from loguru import logger

from src.constants import EventEnum, LabelName, EventType
from src.helpers import get_exception_class
from src.instrumentation import EventCounter, EventGauge


class InvalidTaskEventLabelName(Exception):
    pass


class IEventHandler(ABC):
    def __init__(self, state):
        self._state = state

    def __call__(self, event: Dict[str, Any]):
        self.handle_event(event=event)

    @abstractmethod
    def handle_event(self, event: Dict[str, Any]):
        pass

    @staticmethod
    def _get_label_values_from_task(
        instrument: Union[EventCounter, EventGauge], task: Task
    ) -> Dict[str, Any]:
        labels = {}
        for labelname in instrument.labelnames:
            try:
                value = getattr(task, labelname)
            except AttributeError as e:
                raise InvalidTaskEventLabelName(
                    f"Label names given to counters for task events must represent valid attribute names of a celery task."
                    f' You have used labelname: {labelname}. Available task attributes: {[attr for attr in dir(task) if not attr.startswith("_")]}'
                ) from e
            if labelname == LabelName.EXCEPTION:
                logger.debug(value)
                value = get_exception_class(value)
            labels[labelname] = value

        return labels


class TaskEventHandler(IEventHandler):
    def __init__(self, state, counter: EventCounter):
        super().__init__(state)
        self._counter = counter

    def handle_event(self, event: Dict[str, Any]):
        self._state.event(event)
        task = self._state.tasks.get(event[EventEnum.UUID])
        logger.debug(f"Received event={event[EventEnum.TYPE]} for task={task.name}")

        labels = self._get_label_values_from_task(instrument=self._counter, task=task)
        self._counter.labels(**labels).inc()
        logger.debug(f"Incremented metric={self._counter.name}, labels={labels}")


class TaskStartedEventHandler(TaskEventHandler):
    def __init__(self, state, counter: EventCounter, queuing_time_gauge: EventGauge):
        super().__init__(state, counter)
        self._queuing_time_gauge = queuing_time_gauge

    def handle_event(self, event: Dict[str, Any]):
        super().handle_event(event)
        self._update_queuing_time_gauge(event=event)

    def _update_queuing_time_gauge(self, event: Dict[str, Any]):
        task = self._state.tasks.get(event[EventEnum.UUID])
        labels = self._get_label_values_from_task(
            instrument=self._queuing_time_gauge, task=task
        )

        queue_time = task.started - task.received
        self._queuing_time_gauge.labels(**labels).set(queue_time)

        logger.debug(
            "Updated gauge='{}' value='{}'", self._queuing_time_gauge.name, queue_time
        )


class WorkerStatusHandler(IEventHandler):
    def __init__(self, state, is_online: bool, worker_up_gauge: EventGauge):
        super().__init__(state)
        self._is_online = is_online
        self._worker_up_gauge = worker_up_gauge

    def handle_event(self, event: Dict[str, Any]):
        value = 1 if self._is_online else 0
        event_name = (
            EventType.WORKER_ONLINE if self._is_online else EventType.WORKER_OFFLINE
        )
        hostname = event[EventEnum.HOSTNAME]

        logger.debug("Received event='{}' for hostname='{}'", event_name, hostname)

        self._worker_up_gauge.labels(hostname=hostname).set(value)

        logger.debug("Updated gauge='{}' value='{}'", self._worker_up_gauge.name, value)


class WorkerHeartbeatHandler(IEventHandler):
    def __init__(
        self,
        state,
        worker_up_gauge: EventGauge,
        worker_tasks_active_gauge: EventGauge,
    ):
        super().__init__(state)
        self._worker_up_gauge = worker_up_gauge
        self._worker_tasks_active_gauge = worker_tasks_active_gauge

    def handle_event(self, event: Dict[str, Any]):
        logger.debug(
            "Received event='{}' for hostname='{}'",
            event[EventEnum.TYPE],
            event[EventEnum.HOSTNAME],
        )

        worker_state = self._state.event(event)[0][0]
        active = worker_state.active or 0
        up = 1 if worker_state.alive else 0
        hostname = event[EventEnum.HOSTNAME]
        self._worker_up_gauge.labels(hostname=hostname).set(up)
        self._worker_tasks_active_gauge.labels(hostname=hostname).set(active)
        logger.debug("Updated gauge='{}' value='{}'", self._worker_up_gauge.name, up)
        logger.debug(
            "Updated gauge='{}' value='{}'",
            self._worker_tasks_active_gauge.name,
            active,
        )
