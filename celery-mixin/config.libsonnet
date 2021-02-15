{
  _config+:: {
    // Selectors are inserted between {} in Prometheus queries.

    celerySelector: 'job="celery"',
    taskInterval: '10m',
  },
}
