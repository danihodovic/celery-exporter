# pylint: disable=too-many-arguments, no-self-use

import logging
from unittest.mock import Mock, create_autospec

import pytest
from celery import Task
from prometheus_client import CollectorRegistry

from src.constants import TASK_EVENT_LABELS, EventEnum, EventType, LabelName
from src.event_handlers import InvalidTaskEventLabelName, TaskEventHandler
from src.instrumentation import EventCounter


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
    mock_task = create_autospec(Task, uuid=uuid, hostname=hostname)
    mock_task.configure_mock(name=task_name)
    return mock_task


@pytest.fixture
def counter_name():
    return "counter_name"


@pytest.fixture
def mock_counter(counter_name):
    mock_registry = create_autospec(CollectorRegistry)
    mock_counter = create_autospec(
        EventCounter,
        documentation="some_documentation",
        labelnames=TASK_EVENT_LABELS,
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


class TestTaskEventHandler:
    def test_increments_counter_for_correct_labels(
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

        expected_labels = {LabelName.NAME: task_name, LabelName.HOSTNAME: hostname}

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
