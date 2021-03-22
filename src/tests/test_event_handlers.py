# pylint: disable=too-many-arguments, no-self-use, too-many-locals, too-few-public-methods

import logging
from unittest.mock import Mock, create_autospec

import pytest
from celery import Task
from prometheus_client import CollectorRegistry

from src.constants import TASK_EVENT_LABELS, EventEnum, EventType, LabelName
from src.event_handlers import (
    InvalidTaskEventLabelName,
    TaskEventHandler,
    TaskStartedEventHandler,
)
from src.instrumentation import EventCounter, EventGauge


@pytest.fixture
def uuid():
    return "1234"


@pytest.fixture
def hostname():
    return "this@that.com"


@pytest.fixture
def task_name():
    return "big_task"


@pytest.fixture
def mock_task(uuid, hostname, task_name):
    mock_task = create_autospec(
        Task, uuid=uuid, hostname=hostname, exception=repr(ValueError("some error"))
    )
    mock_task.configure_mock(name=task_name)
    return mock_task


@pytest.fixture
def counter_name():
    return "counter_name"


@pytest.fixture
def mock_registry():
    return create_autospec(CollectorRegistry)


@pytest.fixture
def mock_counter(counter_name, mock_registry):
    mock_counter = create_autospec(
        EventCounter,
        documentation="some_documentation",
        labelnames=[*TASK_EVENT_LABELS, LabelName.EXCEPTION],
        registry=mock_registry,
    )
    mock_counter.configure_mock(name=counter_name)
    return mock_counter


@pytest.fixture
def mock_state(mock_task, uuid):
    mock_state = Mock(tasks={uuid: mock_task})
    return mock_state


@pytest.fixture
def event_type():
    return EventType.TASK_SENT


@pytest.fixture
def mock_event(event_type, uuid):
    return {EventEnum.UUID: uuid, EventEnum.TYPE: event_type}


@pytest.fixture
def queuing_time_gauge_name():
    return "queuing_time_seconds"


@pytest.fixture
def mock_queuing_time_gauge(mock_registry, queuing_time_gauge_name):
    mock_queueing_time_gauge = create_autospec(
        EventGauge,
        documentation="some_gauge_documentation",
        labelnames=[*TASK_EVENT_LABELS, LabelName.EXCEPTION],
        registry=mock_registry,
    )
    mock_queueing_time_gauge.configure_mock(name=queuing_time_gauge_name)
    return mock_queueing_time_gauge


class TestTaskEventHandler:
    def test_increments_event_counter(
        self,
        caplog,
        hostname,
        task_name,
        mock_counter,
        counter_name,
        mock_state,
        mock_event,
        event_type,
    ):
        caplog.set_level(logging.DEBUG)

        task_event_handler = TaskEventHandler(state=mock_state, counter=mock_counter)

        task_event_handler(event=mock_event)

        expected_labels = {
            LabelName.NAME: task_name,
            LabelName.HOSTNAME: hostname,
            LabelName.EXCEPTION: "ValueError",
        }

        mock_counter.labels.assert_called_once_with(**expected_labels)
        mock_counter.labels.return_value.inc.assert_called_once()

        assert f"Received event={event_type} for task={task_name}" in caplog.text
        assert (
            f"Incremented metric={counter_name}, labels={expected_labels}"
            in caplog.text
        )

    def test_raises_invalid_task_event_label_name_error(
        self, caplog, mock_state, mock_counter, mock_event
    ):
        caplog.set_level(logging.DEBUG)
        invalid_labelname = "invalid"
        mock_counter.configure_mock(labelnames=[invalid_labelname])

        task_event_handler = TaskEventHandler(state=mock_state, counter=mock_counter)

        with pytest.raises(InvalidTaskEventLabelName) as err:
            task_event_handler(event=mock_event)

        assert (
            "Label names given to counters for task events must "
            "represent valid attribute names of a celery task." in err.value.args[0]
        )
        assert f"You have used labelname: {invalid_labelname}." in err.value.args[0]


class TestTaskStartedEventHandler:
    def test_increments_event_counter_and_updates_queuing_time_gauge(
        self,
        caplog,
        hostname,
        task_name,
        mock_counter,
        counter_name,
        mock_state,
        mock_event,
        event_type,
        mock_queuing_time_gauge,
        queuing_time_gauge_name,
        mock_task,
    ):
        caplog.set_level(logging.DEBUG)
        task_started = 10
        task_received = 6
        mock_task.configure_mock(started=task_started, received=task_received)

        task_started_event_handler = TaskStartedEventHandler(
            state=mock_state,
            counter=mock_counter,
            queuing_time_gauge=mock_queuing_time_gauge,
        )

        task_started_event_handler(event=mock_event)

        expected_labels = {
            LabelName.NAME: task_name,
            LabelName.HOSTNAME: hostname,
            LabelName.EXCEPTION: "ValueError",
        }

        mock_counter.labels.assert_called_once_with(**expected_labels)
        mock_counter.labels.return_value.inc.assert_called_once()

        assert f"Received event={event_type} for task={task_name}" in caplog.text
        assert (
            f"Incremented metric={counter_name}, labels={expected_labels}"
            in caplog.text
        )

        mock_queuing_time_gauge.labels.assert_called_once_with(**expected_labels)
        mock_queuing_time_gauge.labels.return_value.set.assert_called_once_with(
            task_started - task_received
        )

        assert (
            f"Updated gauge={queuing_time_gauge_name} value={task_started - task_received}"
            in caplog.text
        )
