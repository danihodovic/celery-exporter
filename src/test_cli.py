import time

import pytest
import requests
from celery.contrib.testing.worker import start_worker  # type: ignore
from requests.exceptions import HTTPError


@pytest.mark.celery()
def test_integration(broker, celery_app, threaded_exporter, hostname):
    exporter_url = f"http://localhost:{threaded_exporter.cfg['port']}/metrics"

    @celery_app.task
    def succeed():
        pass

    @celery_app.task
    def fail():
        raise HTTPError("Intentional error")

    time.sleep(1)
    # Before the first worker starts, make sure queues that the exporter is initialized
    # with are available anyway. Queues to be detected from workers should not be there yet
    res = requests.get(exporter_url, timeout=5)
    assert res.status_code == 200
    assert 'celery_queue_length{queue_name="queue_from_command_line"} 0.0' in res.text
    assert (
        'celery_active_worker_count{queue_name="queue_from_command_line"} 0.0'
        in res.text
    )
    assert (
        'celery_active_process_count{queue_name="queue_from_command_line"} 0.0'
        in res.text
    )
    assert 'celery_queue_length{queue_name="celery"}' not in res.text
    assert 'celery_active_worker_count{queue_name="celery"}' not in res.text
    assert 'celery_active_process_count{queue_name="celery"}' not in res.text

    # start worker first so the exporter can fetch and cache queue information
    with start_worker(celery_app, without_heartbeat=False):
        time.sleep(5)
        res = requests.get(exporter_url, timeout=5)
        assert res.status_code == 200
        assert 'celery_queue_length{queue_name="celery"} 0.0' in res.text, res.text

        # TODO: Fix this...
        if broker == "memory":
            assert (
                'celery_active_consumer_count{queue_name="celery"} 0.0' in res.text
            ), res.text
        assert 'celery_active_worker_count{queue_name="celery"} 1.0' in res.text
        assert 'celery_active_process_count{queue_name="celery"} 1.0' in res.text

    succeed.apply_async()
    succeed.apply_async()
    fail.apply_async()

    # assert celery_queue_length when message in broker but no worker start
    res = requests.get(exporter_url, timeout=3)
    assert res.status_code == 200
    assert 'celery_queue_length{queue_name="celery"} 3.0' in res.text

    if broker == "memory":
        assert 'celery_active_consumer_count{queue_name="celery"} 0.0' in res.text
    assert 'celery_active_worker_count{queue_name="celery"} 0.0' in res.text
    assert 'celery_active_process_count{queue_name="celery"} 0.0' in res.text

    # start worker and consume message in broker
    with start_worker(celery_app, without_heartbeat=False):
        time.sleep(2)

    res = requests.get(exporter_url, timeout=3)
    assert res.status_code == 200
    # pylint: disable=line-too-long
    assert (
        f'celery_task_sent_total{{hostname="{hostname}",name="src.test_cli.succeed",queue_name="celery"}} 2.0'
        in res.text
    )
    assert (
        f'celery_task_sent_total{{hostname="{hostname}",name="src.test_cli.fail",queue_name="celery"}} 1.0'
        in res.text
    )
    assert (
        f'celery_task_received_total{{hostname="{hostname}",name="src.test_cli.succeed",queue_name="celery"}} 2.0'
        in res.text
    )
    assert (
        f'celery_task_received_total{{hostname="{hostname}",name="src.test_cli.fail",queue_name="celery"}} 1.0'
        in res.text
    )
    assert (
        f'celery_task_started_total{{hostname="{hostname}",name="src.test_cli.succeed",queue_name="celery"}} 2.0'
        in res.text
    )
    assert (
        f'celery_task_started_total{{hostname="{hostname}",name="src.test_cli.fail",queue_name="celery"}} 1.0'
        in res.text
    )
    assert (
        f'celery_task_succeeded_total{{hostname="{hostname}",name="src.test_cli.succeed",queue_name="celery"}} 2.0'
        in res.text
    )
    assert (
        f'celery_task_failed_total{{exception="HTTPError",hostname="{hostname}",name="src.test_cli.fail",queue_name="celery"}} 1.0'
        in res.text
    )
    assert (
        f'celery_task_runtime_count{{hostname="{hostname}",name="src.test_cli.succeed",queue_name="celery"}} 2.0'
        in res.text
    )
    assert 'celery_queue_length{queue_name="celery"} 0.0' in res.text

    # TODO: Fix this...
    if broker == "memory":
        assert 'celery_active_consumer_count{queue_name="celery"} 0.0' in res.text
    assert 'celery_active_worker_count{queue_name="celery"} 0.0' in res.text
    assert 'celery_active_process_count{queue_name="celery"} 0.0' in res.text


# pylint: disable=too-many-statements
@pytest.mark.celery()
def test_integration_static_labels(
    broker, celery_app, threaded_exporter_static_labels, hostname
):
    exporter_url = (
        f"http://localhost:{threaded_exporter_static_labels.cfg['port']}/metrics"
    )
    # Substring representing static labels in metrics labels
    static_labels_str = ",".join(
        [
            f'{k}="{v}"'
            for k, v in sorted(
                threaded_exporter_static_labels.cfg["static_label"].items()
            )
        ]
    )

    @celery_app.task
    def succeed():
        pass

    @celery_app.task
    def fail():
        raise HTTPError("Intentional error")

    time.sleep(1)
    # Before the first worker starts, make sure queues that the exporter is initialized
    # with are available anyway. Queues to be detected from workers should not be there yet
    res = requests.get(exporter_url, timeout=5)
    assert res.status_code == 200
    assert (
        f'celery_queue_length{{queue_name="queue_from_command_line",{static_labels_str}}} 0.0'
        in res.text
    )
    assert (
        # pylint: disable=line-too-long
        f'celery_active_worker_count{{queue_name="queue_from_command_line",{static_labels_str}}} 0.0'
        in res.text
    )
    assert (
        # pylint: disable=line-too-long
        f'celery_active_process_count{{queue_name="queue_from_command_line",{static_labels_str}}} 0.0'
        in res.text
    )
    assert (
        f'celery_queue_length{{queue_name="celery",{static_labels_str}}}'
        not in res.text
    )
    assert (
        f'celery_active_worker_count{{queue_name="celery",{static_labels_str}}}'
        not in res.text
    )
    assert (
        f'celery_active_process_count{{queue_name="celery",{static_labels_str}}}'
        not in res.text
    )

    # start worker first so the exporter can fetch and cache queue information
    with start_worker(celery_app, without_heartbeat=False):
        time.sleep(5)
        res = requests.get(exporter_url, timeout=5)
        assert res.status_code == 200
        assert (
            f'celery_queue_length{{queue_name="celery",{static_labels_str}}} 0.0'
            in res.text
        ), res.text

        # TODO: Fix this...
        if broker == "memory":
            assert (
                f'celery_active_consumer_count{{queue_name="celery",{static_labels_str}}} 0.0'
                in res.text
            ), res.text
        assert (
            f'celery_active_worker_count{{queue_name="celery",{static_labels_str}}} 1.0'
            in res.text
        )
        assert (
            f'celery_active_process_count{{queue_name="celery",{static_labels_str}}} 1.0'
            in res.text
        )

    succeed.apply_async()
    succeed.apply_async()
    fail.apply_async()

    # assert celery_queue_length when message in broker but no worker start
    res = requests.get(exporter_url, timeout=3)
    assert res.status_code == 200
    assert (
        f'celery_queue_length{{queue_name="celery",{static_labels_str}}} 3.0'
        in res.text
    )

    if broker == "memory":
        assert (
            f'celery_active_consumer_count{{queue_name="celery",{static_labels_str}}} 0.0'
            in res.text
        )
    assert (
        f'celery_active_worker_count{{queue_name="celery",{static_labels_str}}} 0.0'
        in res.text
    )
    assert (
        f'celery_active_process_count{{queue_name="celery",{static_labels_str}}} 0.0'
        in res.text
    )

    # start worker and consume message in broker
    with start_worker(celery_app, without_heartbeat=False):
        time.sleep(2)

    res = requests.get(exporter_url, timeout=3)
    assert res.status_code == 200
    # pylint: disable=line-too-long
    assert (
        f'celery_task_sent_total{{hostname="{hostname}",name="src.test_cli.succeed",queue_name="celery",{static_labels_str}}} 2.0'
        in res.text
    )
    assert (
        f'celery_task_sent_total{{hostname="{hostname}",name="src.test_cli.fail",queue_name="celery",{static_labels_str}}} 1.0'
        in res.text
    )
    assert (
        f'celery_task_received_total{{hostname="{hostname}",name="src.test_cli.succeed",queue_name="celery",{static_labels_str}}} 2.0'
        in res.text
    )
    assert (
        f'celery_task_received_total{{hostname="{hostname}",name="src.test_cli.fail",queue_name="celery",{static_labels_str}}} 1.0'
        in res.text
    )
    assert (
        f'celery_task_started_total{{hostname="{hostname}",name="src.test_cli.succeed",queue_name="celery",{static_labels_str}}} 2.0'
        in res.text
    )
    assert (
        f'celery_task_started_total{{hostname="{hostname}",name="src.test_cli.fail",queue_name="celery",{static_labels_str}}} 1.0'
        in res.text
    )
    assert (
        f'celery_task_succeeded_total{{hostname="{hostname}",name="src.test_cli.succeed",queue_name="celery",{static_labels_str}}} 2.0'
        in res.text
    )
    assert (
        f'celery_task_failed_total{{exception="HTTPError",hostname="{hostname}",name="src.test_cli.fail",queue_name="celery",{static_labels_str}}} 1.0'
        in res.text
    )
    assert (
        f'celery_task_runtime_count{{hostname="{hostname}",name="src.test_cli.succeed",queue_name="celery",{static_labels_str}}} 2.0'
        in res.text
    )
    assert (
        f'celery_queue_length{{queue_name="celery",{static_labels_str}}} 0.0'
        in res.text
    )

    # TODO: Fix this...
    if broker == "memory":
        assert (
            f'celery_active_consumer_count{{queue_name="celery",{static_labels_str}}} 0.0'
            in res.text
        )
    assert (
        f'celery_active_worker_count{{queue_name="celery",{static_labels_str}}} 0.0'
        in res.text
    )
    assert (
        f'celery_active_process_count{{queue_name="celery",{static_labels_str}}} 0.0'
        in res.text
    )
