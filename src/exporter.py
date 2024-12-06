# pylint: disable=protected-access,,attribute-defined-outside-init
import json
import re
import sys
import time
from collections import defaultdict
from typing import Callable, Optional

from celery import Celery
from celery.events.state import State  # type: ignore
from celery.utils import nodesplit  # type: ignore
from celery.utils.time import utcoffset  # type: ignore
from kombu.exceptions import ChannelError  # type: ignore
from loguru import logger
from prometheus_client import CollectorRegistry, Counter, Gauge, Histogram

from .http_server import start_http_server


class Exporter:  # pylint: disable=too-many-instance-attributes,too-many-branches
    state: State = None

    # pylint: disable=too-many-arguments,too-many-positional-arguments
    def __init__(
        self,
        buckets=None,
        worker_timeout_seconds=5 * 60,
        purge_offline_worker_metrics_seconds=10 * 60,
        generic_hostname_task_sent_metric=False,
        initial_queues=None,
        metric_prefix="celery_",
        static_label=None,
    ):
        self.registry = CollectorRegistry(auto_describe=True)
        self.queue_cache = set(initial_queues or [])
        self.worker_last_seen = {}
        self.worker_timeout_seconds = worker_timeout_seconds
        self.purge_offline_worker_metrics_after_seconds = (
            purge_offline_worker_metrics_seconds
        )
        self.generic_hostname_task_sent_metric = generic_hostname_task_sent_metric

        # Static labels
        self.static_label = static_label or {}
        self.static_label_keys = self.static_label.keys()

        self.state_counters = {
            "task-sent": Counter(
                f"{metric_prefix}task_sent",
                "Sent when a task message is published.",
                ["name", "hostname", "queue_name", *self.static_label_keys],
                registry=self.registry,
            ),
            "task-received": Counter(
                f"{metric_prefix}task_received",
                "Sent when the worker receives a task.",
                ["name", "hostname", "queue_name", *self.static_label_keys],
                registry=self.registry,
            ),
            "task-started": Counter(
                f"{metric_prefix}task_started",
                "Sent just before the worker executes the task.",
                ["name", "hostname", "queue_name", *self.static_label_keys],
                registry=self.registry,
            ),
            "task-succeeded": Counter(
                f"{metric_prefix}task_succeeded",
                "Sent if the task executed successfully.",
                ["name", "hostname", "queue_name", *self.static_label_keys],
                registry=self.registry,
            ),
            "task-failed": Counter(
                f"{metric_prefix}task_failed",
                "Sent if the execution of the task failed.",
                [
                    "name",
                    "hostname",
                    "exception",
                    "queue_name",
                    *self.static_label_keys,
                ],
                registry=self.registry,
            ),
            "task-rejected": Counter(
                f"{metric_prefix}task_rejected",
                # pylint: disable=line-too-long
                "The task was rejected by the worker, possibly to be re-queued or moved to a dead letter queue.",
                ["name", "hostname", "queue_name", *self.static_label_keys],
                registry=self.registry,
            ),
            "task-revoked": Counter(
                f"{metric_prefix}task_revoked",
                "Sent if the task has been revoked.",
                ["name", "hostname", "queue_name", *self.static_label_keys],
                registry=self.registry,
            ),
            "task-retried": Counter(
                f"{metric_prefix}task_retried",
                "Sent if the task failed, but will be retried in the future.",
                ["name", "hostname", "queue_name", *self.static_label_keys],
                registry=self.registry,
            ),
        }
        self.celery_worker_up = Gauge(
            f"{metric_prefix}worker_up",
            "Indicates if a worker has recently sent a heartbeat.",
            ["hostname", *self.static_label_keys],
            registry=self.registry,
        )
        self.worker_tasks_active = Gauge(
            f"{metric_prefix}worker_tasks_active",
            "The number of tasks the worker is currently processing",
            ["hostname", *self.static_label_keys],
            registry=self.registry,
        )
        self.celery_task_runtime = Histogram(
            f"{metric_prefix}task_runtime",
            "Histogram of task runtime measurements.",
            ["name", "hostname", "queue_name", *self.static_label_keys],
            registry=self.registry,
            buckets=buckets or Histogram.DEFAULT_BUCKETS,
        )
        self.celery_queue_length = Gauge(
            f"{metric_prefix}queue_length",
            "The number of message in broker queue.",
            ["queue_name", *self.static_label_keys],
            registry=self.registry,
        )
        self.celery_active_consumer_count = Gauge(
            f"{metric_prefix}active_consumer_count",
            "The number of active consumer in broker queue.",
            ["queue_name", *self.static_label_keys],
            registry=self.registry,
        )
        self.celery_active_worker_count = Gauge(
            f"{metric_prefix}active_worker_count",
            "The number of active workers in broker queue.",
            ["queue_name", *self.static_label_keys],
            registry=self.registry,
        )
        self.celery_active_process_count = Gauge(
            f"{metric_prefix}active_process_count",
            "The number of active processes in broker queue.",
            ["queue_name", *self.static_label_keys],
            registry=self.registry,
        )

    def scrape(self):
        if (
            self.worker_timeout_seconds > 0
            or self.purge_offline_worker_metrics_after_seconds > 0
        ):
            self.track_timed_out_workers()
        self.track_queue_metrics()

    def forget_worker(self, hostname):
        if hostname in self.worker_last_seen:
            self.celery_worker_up.labels(hostname=hostname, **self.static_label).set(0)
            self.worker_tasks_active.labels(hostname=hostname, **self.static_label).set(
                0
            )
            logger.debug(
                "Updated gauge='{}' value='{}'", self.worker_tasks_active._name, 0
            )
            logger.debug(
                "Updated gauge='{}' value='{}'", self.celery_worker_up._name, 0
            )
            self.worker_last_seen[hostname]["forgotten"] = True

            # If purging of metrics is enabled we should keep the last seen so that we can
            # use the timestamp to purge the metrics later
            if self.purge_offline_worker_metrics_after_seconds == 0:
                del self.worker_last_seen[hostname]

    def purge_worker_metrics(self, hostname):
        # Prometheus stores a copy of the metrics in memory, so we need to remove them
        # The key of the metrics is a string sequence e.g ('celery(queue_name)', 'host-1(hostname)')
        for label_seq in list(self.worker_tasks_active._metrics.keys()):
            if hostname in label_seq:
                self.worker_tasks_active.remove(*label_seq)

        for label_seq in list(self.celery_worker_up._metrics.keys()):
            if hostname in label_seq:
                self.celery_worker_up.remove(*label_seq)

        for counter in self.state_counters.values():
            for label_seq in list(counter._metrics.keys()):
                if hostname in label_seq:
                    counter.remove(*label_seq)

        for label_seq in list(self.celery_task_runtime._metrics.keys()):
            if hostname in label_seq:
                self.celery_task_runtime.remove(*label_seq)

        del self.worker_last_seen[hostname]

    def track_timed_out_workers(self):
        now = time.time()
        # Make a copy of the last seen dict so we can delete from the dict with no issues
        for hostname, worker_status in list(self.worker_last_seen.items()):
            since = now - worker_status["ts"]
            if since > self.worker_timeout_seconds and not worker_status["forgotten"]:
                logger.info(
                    f"Have not seen {hostname} for {since:0.2f} seconds. "
                    "Removing from metrics"
                )
                self.forget_worker(hostname)

            if self.purge_offline_worker_metrics_after_seconds > 0:
                if since > self.purge_offline_worker_metrics_after_seconds:
                    logger.info(
                        f"Have not seen {hostname} for {since:0.2f} seconds. "
                        "Purging worker metrics"
                    )
                    self.purge_worker_metrics(hostname)

    def track_queue_metrics(self):
        with self.app.connection() as connection:  # type: ignore
            transport = connection.info()["transport"]
            acceptable_transports = [
                "redis",
                "rediss",
                "amqp",
                "amqps",
                "memory",
                "sentinel",
            ]
            if transport not in acceptable_transports:
                logger.debug(
                    f"Queue length tracking is only implemented for {acceptable_transports}"
                )
                return

            concurrency_per_worker = {
                worker: len(stats["pool"].get("processes", []))
                for worker, stats in (self.app.control.inspect().stats() or {}).items()
            }
            processes_per_queue = defaultdict(int)
            workers_per_queue = defaultdict(int)

            # request workers to response active queues
            # we need to cache queue info in exporter in case all workers are offline
            # so that no worker response to exporter will make active_queues return None
            queues = self.app.control.inspect().active_queues() or {}
            for worker, info_list in queues.items():
                for queue_info in info_list:
                    name = queue_info["name"]
                    self.queue_cache.add(name)
                    workers_per_queue[name] += 1
                    processes_per_queue[name] += concurrency_per_worker.get(worker, 0)

            for queue in self.queue_cache:
                if transport in ["amqp", "amqps", "memory"]:
                    consumer_count = rabbitmq_queue_consumer_count(connection, queue)
                    self.celery_active_consumer_count.labels(
                        queue_name=queue, **self.static_label
                    ).set(consumer_count)

                self.celery_active_process_count.labels(
                    queue_name=queue, **self.static_label
                ).set(processes_per_queue[queue])
                self.celery_active_worker_count.labels(
                    queue_name=queue, **self.static_label
                ).set(workers_per_queue[queue])
                length = queue_length(transport, connection, queue)
                if length is not None:
                    self.celery_queue_length.labels(
                        queue_name=queue, **self.static_label
                    ).set(length)

    def track_task_event(self, event):
        self.state.event(event)
        task = self.state.tasks.get(event["uuid"])
        logger.debug("Received event='{}' for task='{}'", event["type"], task.name)

        if event["type"] not in self.state_counters:
            logger.warning("No counter matches task state='{}'", task.state)

        labels = {
            "name": task.name,
            "hostname": get_hostname(task.hostname),
            "queue_name": getattr(task, "queue", "celery"),
            **self.static_label,
        }
        if event["type"] == "task-sent" and self.generic_hostname_task_sent_metric:
            labels["hostname"] = "generic"

        for counter_name, counter in self.state_counters.items():
            _labels = labels.copy()

            if counter_name == "task-failed":
                if counter_name == event["type"]:
                    _labels["exception"] = get_exception_class_name(task.exception)
                else:
                    _labels["exception"] = ""

            if counter_name == event["type"]:
                counter.labels(**_labels).inc()
                logger.debug(
                    "Incremented metric='{}' labels='{}'", counter._name, labels
                )
            elif (
                event["type"] != "task-sent"
            ):  # task-sent is sent by various hosts (webservers, task creators etc.) which cause label cardinality # pylint: disable=line-too-long
                # increase unaffected counters by zero in order to make them visible
                counter.labels(**_labels).inc(0)

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
        hostname = get_hostname(event["hostname"])
        logger.debug("Received event='{}' for hostname='{}'", event_name, hostname)
        self.celery_worker_up.labels(hostname=hostname, **self.static_label).set(value)

        if is_online:
            self.worker_last_seen[hostname] = {
                "ts": reverse_adjust_timestamp(
                    event["timestamp"], event.get("utcoffset")
                ),
                "forgotten": False,
            }
        else:
            self.forget_worker(hostname)

    def track_worker_heartbeat(self, event):
        hostname = get_hostname(event["hostname"])
        logger.debug("Received event='{}' for worker='{}'", event["type"], hostname)

        self.worker_last_seen[hostname] = {
            "ts": reverse_adjust_timestamp(event["timestamp"], event.get("utcoffset")),
            "forgotten": False,
        }
        worker_state = self.state.event(event)[0][0]
        active = worker_state.active or 0
        up = 1 if worker_state.alive else 0
        self.celery_worker_up.labels(hostname=hostname, **self.static_label).set(up)
        self.worker_tasks_active.labels(hostname=hostname, **self.static_label).set(
            active
        )
        logger.debug(
            "Updated gauge='{}' value='{}'", self.worker_tasks_active._name, active
        )
        logger.debug("Updated gauge='{}' value='{}'", self.celery_worker_up._name, up)

    def run(self, click_params):
        logger.remove()
        logger.add(sys.stdout, level=click_params["log_level"])
        self.app = Celery(broker=click_params["broker_url"])
        if click_params["accept_content"] is not None:
            accept_content_list = click_params["accept_content"].split(",")
            logger.info("Setting celery accept_content {}", accept_content_list)
            self.app.config_from_object(dict(accept_content=accept_content_list))
        transport_options = {}
        for transport_option in click_params["broker_transport_option"]:
            if transport_option is not None:
                option, value = transport_option.split("=", 1)
                if option is not None:
                    logger.debug(
                        "Setting celery broker_transport_option {}={}", option, value
                    )
                    transport_options[option] = transform_option_value(value)

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

        self.state = self.app.events.State()  # type: ignore
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

        with self.app.connection() as connection:  # type: ignore
            start_http_server(
                self.registry,
                connection,
                click_params["host"],
                click_params["port"],
                self.scrape,
            )
            while True:
                try:
                    recv = self.app.events.Receiver(connection, handlers=handlers)  # type: ignore
                    recv.capture(limit=None, timeout=None, wakeup=True)  # type: ignore

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


def reverse_adjust_timestamp(
    ts: float, offset: Optional[int] = None, here: Callable[..., float] = utcoffset
) -> float:
    """Adjust timestamp in reverse of celery, based on provided utcoffset."""
    return ts + ((offset or 0) - here()) * 3600


def get_exception_class_name(exception_name: str):
    m = exception_pattern.match(exception_name)
    if m:
        return m.group(1)
    return "UnknownException"


def get_hostname(name: str) -> str:
    """
    Get hostname from celery's hostname.

    Celery's hostname contains either worker's name or Process ID in it.
    >>> get_hostname("workername@hostname")
    'hostname'
    >>> get_hostname("gen531@hostname")
    'hostname'

    Prometheus suggests it:
    > Do not use labels to store dimensions with high cardinality (many different label values)
    """
    _, hostname = nodesplit(name)
    return hostname


def transform_option_value(value: str):
    """
    Make an attempt to transform option value to appropriate type

    Result type:
        - int - if input contains only digits
        - dict - if input may be correctly decoded from JSON string
        - str - in any other cases
    """
    if value.isnumeric():
        return int(value)
    try:
        return json.loads(value)
    except ValueError:
        return value


def redis_queue_length(connection, queue: str) -> int:
    return connection.default_channel.client.llen(queue)


def rabbitmq_queue_length(connection, queue: str) -> int:
    if queue_info := rabbitmq_queue_info(connection, queue):
        return queue_info.message_count
    return 0


def queue_length(transport, connection, queue: str) -> Optional[int]:
    if transport in ["redis", "rediss", "sentinel"]:
        return redis_queue_length(connection, queue)

    if transport in ["amqp", "amqps", "memory"]:
        return rabbitmq_queue_length(connection, queue)

    return None


def rabbitmq_queue_consumer_count(connection, queue: str) -> int:
    if queue_info := rabbitmq_queue_info(connection, queue):
        return queue_info.consumer_count
    return 0


def rabbitmq_queue_info(connection, queue: str):
    try:
        queue_info = connection.default_channel.queue_declare(queue=queue, passive=True)
        return queue_info
    except ChannelError as ex:
        if "NOT_FOUND" in ex.message:
            logger.debug(f"Queue '{queue}' not found")
            return None
        raise ex
