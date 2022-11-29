{
  _config+:: {
    // Selectors are inserted between {} in Prometheus queries.
    celerySelector: 'job=~"celery|celery-exporter"',
    celeryTasksOverviewUid: 'celery-tasks-overview-32s3',

    tags: ['celery', 'celery-mixin'],

    // The task interval is used as the interval for Prometheus alerts of failed tasks and the Grafana graph visualizing task state over time.
    taskInterval: '10m',
  },
}
