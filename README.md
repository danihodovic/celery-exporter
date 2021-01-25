# celery-exporter [![Build Status](https://ci.depode.com/api/badges/danihodovic/celery-exporter/status.svg)](https://ci.depode.com/danihodovic/celery-exporter)
```
Usage: cli.py [OPTIONS]

  @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
  @@@@@@@@@@@@@@@@@@@((((((((((((((((((((((@@@@@@@@@@@@@@@@@@@
  @@@@@@@@@@@@@@((((((((((((((@@((((((((((((((((@@@@@@@@@@@@@@
  @@@@@@@@@@@((((((((((((((((@@@(((((((((((((((((((@@@@@@@@@@@
  @@@@@@@@(((((((((((((((((((@@@@(((((@(((((((((((((((@@@@@@@@
  @@@@@@(((((((((((((((@@((((@@@@@(((@@(((((((((((((((((@@@@@@
  @@@@@((((((((((((((((@@@((@@@@@@@(@@@@((((((((((((((((((@@@@
  @@@(((((((((((((((((@@@@(@@@@@@@@(@@@@@((((((((((((((((((@@@
  @@(((((((((((((((((@@@@@@@@@@@@@@(@@@@@@((((((((((((((((((@@
  @(((((((((((((((((@@@@@@@@@@@@@@@@@@@@@@@((((((((((((((((((@
  @(((((((((((((((((@@@@@@@@@@@@@@@@@@@@@@@((((((((((((((((((@
  @(((((((((((((((((@@@@@@@@@@@@@@@@@@@@@@@(((((((((((((((((((
  (((((((((((((((((((@@@@@@@@@@@@@@@@@@@@@@(((((((((((((((((((
  @(((((((((((@@@@((((@@@@@@@@@@@@@@@@@@@(((((@@@@((((((((((((
  @((((((((((((@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@((((((((((((@
  @((((((((((((((@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@((((((((((((((@
  @@((((((((((((((((((((((((((((((((((((((((((((((((((((((((@@
  @@@(((((((((((((@@@@@@@@@@@@@@@@@@@@@@@@@@@@(((((((((((((@@@
  @@@@((((((((((((@@@@@@@@@@@@@@@@@@@@@@@@@@@@((((((((((((@@@@
  @@@@@@((((((((((((((((((((((((((((((((((((((((((((((((@@@@@@
  @@@@@@@@((((((((((((((@@@@@@@@@@@@@@@@((((((((((((((@@@@@@@@
  @@@@@@@@@@(((((((((((((@@@@@@@@@@@@@@(((((((((((((@@@@@@@@@@
  @@@@@@@@@@@@@@(((((((((((#@@@@@@@@@(((((((((((&@@@@@@@@@@@@@
  @@@@@@@@@@@@@@@@@@((((((((((((((((((((((((@@@@@@@@@@@@@@@@@@

  A Prometheus exporter for Celery.

  Metrics exposed:

  task_sent_total
  Sent when a task message is published.

  task_received_total
  Sent when the worker receives a task.

  task_started_total
  Sent just before the worker executes the task.

  task_failed_total
  Sent if the execution of the task failed.

  task_retried_total
  Sent if the task failed, but will be retried in the future.

  task_succeeded_total
  Sent if the task executed successfully.

  task_revoked_total
  Sent if the task has been revoked.

  task_rejected_total
  The task was rejected by the worker, possibly to be re-queued or moved to a dead letter queue.

Options:
  --broker-url TEXT  The url to the broker, e.g redis://1.2.3.4  [required]
  --port INTEGER     The port the exporter will listen on  [default: 9900]
  --frequency FLOAT  The frequency at which the exporter will pull metrics
                     from Celery  [default: 15]

  --help             Show this message and exit.
```
