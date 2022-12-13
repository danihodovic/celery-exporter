local grafana = import 'github.com/grafana/grafonnet-lib/grafonnet/grafana.libsonnet';
local annotation = grafana.annotation;

{
  _config+:: {
    // Selectors are inserted between {} in Prometheus queries.
    celerySelector: 'job=~"celery|celery-exporter"',

    grafanaUrl: 'https://grafana.com',

    celeryIgnoredTasks: 'None',

    celeryTasksOverviewUid: 'celery-tasks-overview-32s3',
    celeryTasksByTaskUid: 'celery-tasks-by-task-32s3',

    celeryTasksOverviewUrl: '%s/d/%s/celery-tasks-overview' % [self.grafanaUrl, self.celeryTasksOverviewUid],
    celeryTasksByTaskUrl: '%s/d/%s/celery-tasks-by-task' % [self.grafanaUrl, self.celeryTasksByTaskUid],

    tags: ['celery', 'celery-mixin'],

    // If you have autoscaling workers then you maybe do not want to alert on workers that are down.
    celeryWorkerDownAlertEnabled: true,
    // The task interval is used as the interval for Prometheus alerts of failed tasks.
    celeryTaskFailedInterval: '10m',
    celeryTaskFailedThreshold: '5',  // percent

    // Custom annotations to display in graphs
    annotation: {
      enabled: false,
      name: 'Deploys',
      datasource: '-- Grafana --',
      tags: [],
    },

    customAnnotation:: if $._config.annotation.enabled then
      annotation.datasource(
        $._config.annotation.name,
        datasource=$._config.annotation.datasource,
        hide=false,
      ) + {
        target: {
          matchAny: true,
          tags: $._config.annotation.tags,
          type: 'tags',
        },
      } else {},
  },
}
