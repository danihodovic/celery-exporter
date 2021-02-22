{
  prometheusAlerts+:: {
    groups+: [
      {
        name: 'celery',
        rules: [
          {
            alert: 'CeleryTaskFailed',
            expr: |||
              increase(celery_task_failed_total{%(celerySelector)s}[%(taskInterval)s]) > 1
            ||| % $._config,
            labels: {
              severity: 'warning',
            },
            annotations: {
              summary: 'A Celery task has failed to complete.',
              description: 'The task {{ $labels.name }} failed to complete.',
            },
          },
          {
            alert: 'CeleryWorkerDown',
            expr: |||
              celery_worker_up{%(celerySelector)s} == 0
            ||| % $._config,
            labels: {
              severity: 'warning',
            },
            annotations: {
              summary: 'A Celery worker is offline.',
              description: 'The Celery worker {{ $labels.hostname }} is offline.',
            },
          },
        ],
      },
    ],
  },
}
