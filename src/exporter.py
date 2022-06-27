# pylint: disable=protected-access,,attribute-defined-outside-init
import re
import sys
import time
import threading

from celery import Celery
from celery.events.state import State  # type: ignore
from loguru import logger
from prometheus_client import CollectorRegistry, Counter, Gauge, Histogram

from .http_server import start_http_server


class Exporter:  # pylint: disable=too-many-instance-attributes,too-many-branches
    state: State = None

    def __init__(self, buckets=None):
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
        self.celery_task_runtime = Histogram(
            "celery_task_runtime",
            "Histogram of task runtime measurements.",
            ["name", "hostname"],
            registry=self.registry,
            buckets=buckets or Histogram.DEFAULT_BUCKETS,
        )
        self.celery_queue_length = Gauge(
            "celery_queue_length",
            "The number of message in broker queue.",
            ["queue_name"],
            registry=self.registry,
        )
        self.celery_active_consumer_count = Gauge(
            "celery_active_consumer_count",
            "The number of active consumer in broker queue.",
            ["queue_name"],
            registry=self.registry,
        )

    def track_queue_length(self, track_queues, track_interval):
        with self.app.connection() as connection:
            while True:
                for queue in track_queues:
                    try:
                        ret = connection.default_channel.queue_declare(
                            queue=queue, passive=True
                        )
                        length, consumer_count = ret.message_count, ret.consumer_count
                    except Exception as ex:  # pylint: disable=broad-except
                        logger.exception(
                            f"Get length for queue {queue} failed: {str(ex)}"
                        )
                        length = 0
                        consumer_count = 0
                    self.celery_queue_length.labels(queue_name=queue).set(length)
                    self.celery_active_consumer_count.labels(queue_name=queue).set(
                        consumer_count
                    )

                time.sleep(track_interval)

    def track_task_event(self, event):
        self.state.event(event)
        task = self.state.tasks.get(event["uuid"])
        logger.debug("Received event='{}' for task='{}'", event["type"], task.name)

        if event["type"] not in self.state_counters:
            logger.warning("No counter matches task state='{}'", task.state)

        labels = {"name": task.name, "hostname": task.hostname}

        for counter_name, counter in self.state_counters.items():
            _labels = labels.copy()

            if counter_name == "task-failed":
                if counter_name == event["type"]:
                    _labels["exception"] = get_exception_class(task.exception)
                else:
                    _labels["exception"] = ""

            if counter_name == event["type"]:
                counter.labels(**_labels).inc()
            else:
                # increase unaffected counters by zero in order to make them visible
                counter.labels(**_labels).inc(0)

            logger.debug("Incremented metric='{}' labels='{}'", counter._name, labels)

        # observe task runtime
        if event["type"] == "task-succeeded":
            self.celery_task_runtime.labels(**labels).observe(task.runtime)
            logger.debug(
                "Observed metric='{}' labels='{}': {}s",
                self.celery_task_runtime._name,
                labels,
                task.runtime,
            )

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
        logger.remove()
        logger.add(sys.stdout, level=click_params["log_level"])
        self.app = Celery(broker=click_params["broker_url"])
        transport_options = {}
        for transport_option in click_params["broker_transport_option"]:
            if transport_option is not None:
                option, value = transport_option.split("=", 1)
                if option is not None:
                    logger.debug(
                        "Setting celery broker_transport_option {}={}", option, value
                    )
                    if value.isnumeric():
                        transport_options[option] = int(value)
                    else:
                        transport_options[option] = value

        if transport_options is not None:
            self.app.conf["broker_transport_options"] = transport_options

        ssl_options = {}
        for ssl_option in click_params["broker_ssl_option"]:
            if ssl_option is not None:
                option, value = ssl_option.split("=", 1)
                if option is not None:
                    logger.debug("Setting celery ssl_option {}={}", option, value)
                    if value.isnumeric():
                        ssl_options[option] = int(value)
                    else:
                        ssl_options[option] = value

        if ssl_options is not None:
            self.app.conf["broker_use_ssl"] = ssl_options

        self.state = self.app.events.State()
        self.retry_interval = click_params["retry_interval"]
        if self.retry_interval:
            logger.debug("Using retry_interval of {} seconds", self.retry_interval)

        handlers = {
            "worker-heartbeat": self.track_worker_heartbeat,
            "worker-online": lambda event: self.track_worker_status(event, True),
            "worker-offline": lambda event: self.track_worker_status(event, False),
        }
        for key in self.state_counters:
            handlers[key] = self.track_task_event

        if click_params["track_queue"]:
            threading.Thread(
                target=self.track_queue_length,
                args=(
                    click_params["track_queue"],
                    click_params["queue_track_interval"],
                ),
                daemon=True,
            ).start()

        with self.app.connection() as connection:
            start_http_server(self.registry, connection, click_params["port"])
            while True:
                try:
                    recv = self.app.events.Receiver(connection, handlers=handlers)
                    recv.capture(limit=None, timeout=None, wakeup=True)

                except (KeyboardInterrupt, SystemExit) as ex:
                    raise ex

                except Exception as e:  # pylint: disable=broad-except
                    logger.exception(
                        "celery-exporter exception '{}', retrying in {} seconds.",
                        str(e),
                        self.retry_interval,
                    )
                    if self.retry_interval == 0:
                        raise e

                time.sleep(self.retry_interval)


exception_pattern = re.compile(r"^(\w+)\(")


def get_exception_class(exception_name: str):
    m = exception_pattern.match(exception_name)
    assert m
    return m.group(1)
