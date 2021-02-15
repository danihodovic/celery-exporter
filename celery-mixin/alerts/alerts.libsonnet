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
        ],
      },
    ],
  },
}
