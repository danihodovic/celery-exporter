local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';
local annotation = g.dashboard.annotation;

{
  _config+:: {
    // Selectors are inserted between {} in Prometheus queries.
    celerySelector: 'job=~".*celery.*"',

    grafanaUrl: 'https://grafana.com',

    celeryIgnoredTasks: 'None',
    celeryIgnoredQueues: 'None',

    celeryTasksOverviewUid: 'celery-tasks-overview-32s3',
    celeryTasksByTaskUid: 'celery-tasks-by-task-32s3',

    celeryTasksOverviewUrl: '%s/d/%s/celery-tasks-overview' % [self.grafanaUrl, self.celeryTasksOverviewUid],
    celeryTasksByTaskUrl: '%s/d/%s/celery-tasks-by-task' % [self.grafanaUrl, self.celeryTasksByTaskUid],

    tags: ['celery', 'celery-mixin'],

    // If you have autoscaling workers then you maybe do not want to alert on workers that are down.
    celeryWorkerDownAlertEnabled: true,
    celeryCeleryHighQueueLengthAlertEnabled: true,
    // The task interval is used as the interval for Prometheus alerts of failed tasks.
    celeryTaskFailedInterval: '10m',
    celeryTaskFailedThreshold: '5',  // percent
    celeryHighQueueLengthInterval: '20m',
    celeryHighQueueLengthThreshold: '100',
    celeryWorkerDownInterval: '15m',

    // Custom annotations to display in graphs
    annotation: {
      enabled: false,
      name: 'Custom Annotation',
      datasource: '-- Grafana --',
      iconColor: 'green',
      tags: [],
    },

    customAnnotation:: if $._config.annotation.enabled then
      annotation.withName($._config.annotation.name) +
      annotation.withIconColor($._config.annotation.iconColor) +
      annotation.withHide(false) +
      annotation.datasource.withUid($._config.annotation.datasource) +
      annotation.target.withMatchAny(true) +
      annotation.target.withTags($._config.annotation.tags) +
      annotation.target.withType('tags')
    else {},
  },
}
