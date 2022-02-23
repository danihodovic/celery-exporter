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


@click.command(help=cmd_help)
@click.option(
    "--broker-url", required=True, help="The url to the broker, e.g redis://1.2.3.4"
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
@click.option(
    "--log-level",
    default="INFO",
    show_default=True,
)
def cli(broker_url, port, buckets, log_level):  # pylint: disable=unused-argument
    formatted_buckets = list(map(float, buckets.split(",")))
    ctx = click.get_current_context()
    Exporter(formatted_buckets).run(ctx.params)
