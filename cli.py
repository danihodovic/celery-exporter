from src.cli import cli

if __name__ == "__main__":
    # pylint: disable=no-value-for-parameter,unexpected-keyword-arg
    cli(auto_envvar_prefix="CELERY_EXPORTER")
