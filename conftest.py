import socket
# import boto3
import threading

import pytest

from src.exporter import Exporter


def pytest_addoption(parser):
    parser.addoption(
        "--broker",
        action="store",
        default="redis",
        help="What broker to use in tests",
        choices=("redis", "rabbitmq", "sqs", "memory"),
    )
    parser.addoption(
        "--loglevel",
        action="store",
        default="INFO",
        help="Log level of the exporter and celery worker in tests",
        choices=("DEBUG", "INFO", "WARNING", "ERROR"),
    )


@pytest.fixture(scope="session")
def broker(request):
    return request.config.getoption("--broker")


@pytest.fixture(scope="session")
def log_level(request):
    return request.config.getoption("--loglevel")


@pytest.fixture(scope="session")
def celery_config(broker):
    config = dict(
        task_send_sent_event=True,
        worker_send_task_events=True,
    )
    if broker == "redis":
        config["broker_url"] = "redis://localhost:6379"  # type: ignore
    elif broker == "rabbitmq":
        config["broker_url"] = "amqp://guest:guest@localhost:5672"  # type: ignore
    elif broker == "sqs":
        config["broker_url"] = "sqs://test:test@localhost:4566"  # type: ignore
        config["broker_transport_options"] = dict(
            polling_interval=0.3,
            wait_time_seconds=0.5,
        )

        # queue = sqs.create_queue(QueueName='test', Attributes={'DelaySeconds': '5'})
        # broker_transport_options = {'polling_interval': 0.3}
# broker_transport_options = {'queue_name_prefix': 'celery-'}
# broker_transport_options = {
#     'predefined_queues': {
#         'my-q': {
#             'url': 'https://ap-southeast-2.queue.amazonaws.com/123456/my-q',
#             'access_key_id': 'xxx',
#             'secret_access_key': 'xxx',
#         }
#     }
# }
    elif broker == "memory":
        config["broker_url"] = "memory://localhost/"  # type: ignore

    return config


# https://github.com/celery/celery/pull/6632
@pytest.fixture(scope="session")
def celery_worker_parameters(log_level):
    return dict(
        loglevel=log_level,
        without_heartbeat=False,
    )


@pytest.fixture(scope="session")
def celery_enable_logging(log_level):
    return log_level == "DEBUG"


@pytest.fixture(scope="session")
def find_free_port():
    """
    https://gist.github.com/bertjwregeer/0be94ced48383a42e70c3d9fff1f4ad0
    """

    def _find_free_port():

        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(("0.0.0.0", 0))
        portnum = s.getsockname()[1]
        s.close()

        return portnum

    return _find_free_port


@pytest.fixture()
def exporter_instance(find_free_port, celery_config, log_level):
    cfg = {
        "port": find_free_port(),
        "broker_url": celery_config["broker_url"],
        "broker_transport_option": ["visibility_timeout=7200"],
        "broker_ssl_option": [],
        "retry_interval": 5,
        "log_level": log_level,
        "accept_content": None,
    }
    exporter = Exporter()
    setattr(exporter, "cfg", cfg)
    yield exporter


@pytest.fixture()
def threaded_exporter(exporter_instance):
    thread = threading.Thread(
        target=exporter_instance.run, args=(exporter_instance.cfg,), daemon=True
    )
    thread.start()
    yield exporter_instance


@pytest.fixture()
def hostname():
    return socket.gethostname()


# session = boto3.session.Session(profile_name=local_aws_profile)
# s3_resource = session.resource("s3", endpoint_url=local_s3_url)
# broker_transport_options = {'polling_interval': 0.3}
# broker_transport_options = {'queue_name_prefix': 'celery-'}
# broker_transport_options = {
#     'predefined_queues': {
#         'my-q': {
#             'url': 'https://ap-southeast-2.queue.amazonaws.com/123456/my-q',
#             'access_key_id': 'xxx',
#             'secret_access_key': 'xxx',
#         }
#     }
# }

# >>> import boto3
#   2
#   3 session = boto3.Session(
#   4     aws_access_key_id="123",
#   5     aws_secret_access_key="345",
#   6 )                                                                                                                                                   [Meta+Enter] Execute
# sqs = session.resource("sqs", endpoint_url="http://localhost:4566")
# queue = sqs.create_queue(QueueName='test', Attributes={'DelaySeconds': '5'})
# response = queue.send_message(MessageBody='world')
