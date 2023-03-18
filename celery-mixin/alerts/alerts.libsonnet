{
  prometheusAlerts+:: {
    groups+: [
      {
        name: 'celery',
        rules: std.prune([
          {
            alert: 'CeleryTaskHighFailRate',
            expr: |||
              sum(
                increase(
                  celery_task_failed_total{
                    %(celerySelector)s,
                    queue_name!~"%(celeryIgnoredQueues)s",
                    name!~"%(celeryIgnoredTasks)s"
                  }[%(celeryTaskFailedInterval)s]
                )
              )  by (job, namespace, queue_name, name)
              /
              sum(
                increase(
                  celery_task_succeeded_total{
                    %(celerySelector)s,
                    queue_name!~"%(celeryIgnoredQueues)s",
                    name!~"%(celeryIgnoredTasks)s"
                  }[%(celeryTaskFailedInterval)s]
                )
              )  by (job, namespace, queue_name, name)
              * 100 > %(celeryTaskFailedThreshold)s
            ||| % $._config,
            annotations: {
              summary: 'Celery high task fail rate.',
              description: 'More than %(celeryTaskFailedThreshold)s%% tasks failed for the task {{ $labels.queue_name }}/{{ $labels.name }} the past %(celeryTaskFailedInterval)s.' % $._config,
              dashboard_url: $._config.celeryTasksByTaskUrl + '?&var-queue_name={{ $labels.queue_name }}&var-task={{ $labels.name }}',
            },
            labels: {
              severity: 'warning',
            },
          },
          if $._config.celeryCeleryHighQueueLengthAlertEnabled then {
            alert: 'CeleryHighQueueLength',
            expr: |||
              sum(
                celery_queue_length{
                  %(celerySelector)s,
                  queue_name!~"%(celeryIgnoredQueues)s"
                }
              )  by (job, namespace, queue_name)
              > %(celeryHighQueueLengthThreshold)s
            ||| % $._config,
            'for': $._config.celeryHighQueueLengthInterval,
            labels: {
              severity: 'warning',
            },
            annotations: {
              summary: 'Celery high queue length.',
              description: 'More than %(celeryHighQueueLengthThreshold)s tasks in the queue {{ $labels.queue_name }} the past %(celeryHighQueueLengthInterval)s.' % $._config,
            },
          },
          if $._config.celeryWorkerDownAlertEnabled then {
            alert: 'CeleryWorkerDown',
            expr: |||
              celery_worker_up{%(celerySelector)s} == 0
            ||| % $._config,
            'for': '15m',
            labels: {
              severity: 'warning',
            },
            annotations: {
              summary: 'A Celery worker is offline.',
              description: 'The Celery worker {{ $labels.hostname }} is offline.',
            },
          },
        ]),
      },
    ],
  },
}
