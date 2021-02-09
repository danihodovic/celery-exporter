import threading
import time

import pytest
import requests
from click.testing import CliRunner
from requests.exceptions import HTTPError

from .cli import cli


@pytest.mark.celery()
def test_integration(celery_app, celery_worker):
    def run():
        CliRunner().invoke(cli, ["--broker-url=memory://localhost", "--port=23000"])

    threading.Thread(target=run, daemon=True).start()

    @celery_app.task
    def succeed():
        pass

    @celery_app.task
    def fail():
        raise HTTPError("Big, big error")

    celery_worker.reload()
    succeed.apply_async()
    succeed.apply_async()
    fail.apply_async()

    time.sleep(2)
    res = requests.get("http://localhost:23000/metrics")
    assert res.status_code == 200

    # pylint: disable=line-too-long
    assert (
        f'celery_task_received_total{{hostname="{celery_worker.hostname}",name="src.test_cli.succeed"}} 2.0'
        in res.text
    )
    assert (
        f'celery_task_received_total{{hostname="{celery_worker.hostname}",name="src.test_cli.fail"}} 1.0'
        in res.text
    )
    assert (
        f'celery_task_started_total{{hostname="{celery_worker.hostname}",name="src.test_cli.succeed"}} 2.0'
        in res.text
    )
    assert (
        f'celery_task_started_total{{hostname="{celery_worker.hostname}",name="src.test_cli.fail"}} 1.0'
        in res.text
    )
    assert (
        f'celery_task_succeeded_total{{hostname="{celery_worker.hostname}",name="src.test_cli.succeed"}} 2.0'
        in res.text
    )
    assert (
        f'celery_task_failed_total{{exception="HTTPError",hostname="{celery_worker.hostname}",name="src.test_cli.fail"}} 1.0'
        in res.text
    )
