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
                    name!~"%(celeryIgnoredTasks)s"
                  }[%(celeryTaskFailedInterval)s]
                )
              )  by (job, namespace, name)
              /
              sum(
                rate(
                  celery_task_succeeded_total{
                    %(celerySelector)s,
                    name!~"%(celeryIgnoredTasks)s"
                  }[%(celeryTaskFailedInterval)s]
                )
              )  by (job, namespace, name)
              * 100 > %(celeryTaskFailedThreshold)s
            ||| % $._config,
            annotations: {
              summary: 'Celery high task fail rate.',
              description: 'More than %(celeryTaskFailedThreshold)s%% tasks failed for the task {{ $labels.namespace }}/{{ $labels.name }} the past %(celeryTaskFailedInterval)s.' % $._config,
              dashboard_url: $._config.celeryTasksByTaskUrl + '?&var-task={{ $labels.name }}',
            },
            labels: {
              severity: 'warning',
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
