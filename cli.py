from src.cli import cli

if __name__ == "__main__":
    cli(auto_envvar_prefix="CELERY_EXPORTER_")  # pylint: disable=no-value-for-parameter
