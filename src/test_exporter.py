from .exporter import transform_option_value


def test_transform_option_value():
    test_cases = [
        {"input": "1423", "expected": 1423},
        {"input": '{"password": "pass"}', "expected": {"password": "pass"}},
        {
            "input": '{invalid_json: "value"}',
            "expected": '{invalid_json: "value"}',
        },
        {"input": "my_master", "expected": "my_master"},
    ]

    for case in test_cases:
        assert transform_option_value(case["input"]) == case["expected"]


def _connection_raising(reply_text):
    from unittest.mock import MagicMock

    from kombu.exceptions import ChannelError

    connection = MagicMock()
    connection.default_channel.queue_declare.side_effect = ChannelError(
        reply_text=reply_text
    )
    return connection


def test_rabbitmq_queue_info_not_found_returns_none():
    from .exporter import rabbitmq_queue_info

    connection = _connection_raising("NOT_FOUND - no queue 'q' in vhost '/'")
    assert rabbitmq_queue_info(connection, "q") is None


def test_rabbitmq_queue_info_access_refused_returns_none():
    from .exporter import rabbitmq_queue_info

    connection = _connection_raising(
        "ACCESS_REFUSED - access to queue 'q' in vhost '/' refused for user 'u'"
    )
    assert rabbitmq_queue_info(connection, "q") is None


def test_rabbitmq_queue_info_other_channel_errors_raise():
    import pytest
    from kombu.exceptions import ChannelError

    from .exporter import rabbitmq_queue_info

    connection = _connection_raising("PRECONDITION_FAILED - inequivalent arg")
    with pytest.raises(ChannelError):
        rabbitmq_queue_info(connection, "q")
