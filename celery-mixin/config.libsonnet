local grafana = import 'github.com/grafana/grafonnet-lib/grafonnet/grafana.libsonnet';
local annotation = grafana.annotation;

{
  _config+:: {
    // Selectors are inserted between {} in Prometheus queries.
    celerySelector: 'job=~"celery|celery-exporter"',

    celeryTasksOverviewUid: 'celery-tasks-overview-32s3',
    celeryTasksByTaskUid: 'celery-tasks-by-task-32s3',

    tags: ['celery', 'celery-mixin'],

    // The task interval is used as the interval for Prometheus alerts of failed tasks and the Grafana graph visualizing task state over time.
    taskInterval: '10m',

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
