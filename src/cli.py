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
    default=9808,
    show_default=True,
    help="The port the exporter will listen on",
)
def cli(broker_url, port):  # pylint: disable=unused-argument
    ctx = click.get_current_context()
    Exporter().run(ctx.params)
