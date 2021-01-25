import click
import pretty_errors  # pylint: disable=unused-import

from .exporter import Exporter
from .help import cmd_help

# https://github.com/pallets/click/issues/448#issuecomment-246029304
click.core._verify_python3_env = lambda: None  # pylint: disable=protected-access


@click.command(help=cmd_help)
@click.option(
    "--broker-url", required=True, help="The url to the broker, e.g redis://1.2.3.4"
)
@click.option(
    "--port",
    type=int,
    default=9900,
    show_default=True,
    help="The port the exporter will listen on",
)
@click.option(
    "--frequency",
    default=15,
    show_default=True,
    type=float,
    help="The frequency at which the exporter will pull metrics from Celery",
)
def cli(broker_url, port, frequency):  # pylint: disable=unused-argument
    ctx = click.get_current_context()
    Exporter(ctx.params).run()
