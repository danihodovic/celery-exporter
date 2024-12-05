import click

# pylint: disable=unused-import
import pretty_errors  # type: ignore
from prometheus_client import Histogram

from .exporter import Exporter
from .help import cmd_help

# https://github.com/pallets/click/issues/448#issuecomment-246029304
# pylint: disable=protected-access
click.core._verify_python3_env = lambda: None  # type: ignore

default_buckets_str = ",".join(map(str, Histogram.DEFAULT_BUCKETS))


def _comma_seperated_argument(_ctx, _param, value):
    if value is not None:
        return value.split(",")
    return []


# Accepts value string in format "key=val". Returns dict {key: val}.
# * If value is None - returns empty dict
def _eq_sign_separated_argument_to_dict(_ctx, _param, value):
    if value is not None:
        dict_of_key_value_pairs = {}
        for key_value_pair in value:
            key, val = key_value_pair.split("=")
            dict_of_key_value_pairs[key] = val
        return dict_of_key_value_pairs
    return {}


@click.command(help=cmd_help)
@click.option(
    "--broker-url",
    required=True,
    help="The url to the broker, e.g redis://1.2.3.4",
)
@click.option(
    "--broker-transport-option",
    required=False,
    default=[None],
    multiple=True,
    help="Celery broker transport option, e.g visibility_timeout=18000",
)
@click.option(
    "--broker-ssl-option",
    required=False,
    default=[None],
    multiple=True,
    help="Celery broker ssl option, e.g certfile=/var/ssl/amqp-server-cert.pem",
)
@click.option(
    "--accept-content",
    required=False,
    default=None,
    help="Celery accept content options, e.g 'json,pickle'",
)
@click.option(
    "--retry-interval",
    required=False,
    default=0,
    help="Broker exception retry interval in seconds, default is 0 for no retry",
)
@click.option(
    "--host",
    default="0.0.0.0",
    show_default=True,
    help="The host the exporter will listen on",
)
@click.option(
    "--port",
    type=int,
    default=9808,
    show_default=True,
    help="The port the exporter will listen on",
)
@click.option(
    "--buckets",
    default=default_buckets_str,
    show_default=True,
    help="Buckets for runtime histogram",
)
@click.option("--log-level", default="INFO", show_default=True)
@click.option(
    "--worker-timeout",
    default=5 * 60,
    show_default=True,
    help="If no heartbeat has been recieved from a worker in this many seconds, "
    "that a worker will be considered dead. If set to 0, workers will never be "
    "timed out",
)
@click.option(
    "--purge-offline-worker-metrics",
    default=10 * 60,
    show_default=True,
    help="If no heartbeat has been recieved from a worker in this many seconds, "
    "that a worker will be considered dead. Metrics will be purged for this worker "
    "after this many seconds. If set to 0, metrics will never be purged. Helps "
    "with keeping the cardinality of the metrics low.",
)
@click.option(
    "--generic-hostname-task-sent-metric",
    default=False,
    is_flag=True,
    help="The metric celery_task_sent_total will be labeled with a generic hostname. "
    "This option helps with label cardinality when using a dynamic number of clients "
    "which create tasks. The default behavior is to label the metric with the client's hostname. "
    "Knowing which client sent a task might not be useful for many use cases as for example in "
    "Kubernetes environments where the client's hostname is a random string.",
)
@click.option(
    "-Q",
    "--queues",
    default=None,
    show_default=False,
    callback=_comma_seperated_argument,
    help="A comma seperated list of queues to force metrics to appear for. "
    "Queues not included in this setting will not appear in metrics until at least one worker has "
    "been seen to follow that queue.",
)
@click.option(
    "--metric-prefix",
    default="celery_",
    help="Prefix all metrics with a string. "
    "This option replaces the 'celery_*' part with a custom prefix. ",
)
@click.option(
    "--static-label",
    required=False,
    default=None,
    multiple=True,
    callback=_eq_sign_separated_argument_to_dict,
    help="Add label with static value to all metrics",
)
def cli(  # pylint: disable=too-many-arguments,too-many-positional-arguments,too-many-locals
    broker_url,
    broker_transport_option,
    accept_content,
    retry_interval,
    host,
    port,
    buckets,
    log_level,
    broker_ssl_option,
    worker_timeout,
    purge_offline_worker_metrics,
    generic_hostname_task_sent_metric,
    queues,
    metric_prefix,
    static_label,
):  # pylint: disable=unused-argument
    formatted_buckets = list(map(float, buckets.split(",")))
    ctx = click.get_current_context()
    Exporter(
        formatted_buckets,
        worker_timeout,
        purge_offline_worker_metrics,
        generic_hostname_task_sent_metric,
        queues,
        metric_prefix,
        static_label,
    ).run(ctx.params)
