{
  _config+:: {
    local this = self,

    // Selectors are inserted between {} in Prometheus queries.
    celerySelector: 'job=~".*celery.*"',

    // Default datasource name
    datasourceName: 'default',

    // Opt-in to multiCluster dashboards by overriding this and the clusterLabel.
    showMultiCluster: false,
    clusterLabel: 'cluster',

    grafanaUrl: 'https://grafana.com',

    celeryIgnoredTasks: 'None',
    celeryIgnoredQueues: 'None',

    // If you have autoscaling workers then you maybe do not want to alert on workers that are down.
    celeryWorkerDownAlertEnabled: true,
    celeryCeleryHighQueueLengthAlertEnabled: true,
    // The task interval is used as the interval for Prometheus alerts of failed tasks.
    celeryTaskFailedInterval: '10m',
    celeryTaskFailedThreshold: '5',  // percent
    celeryHighQueueLengthInterval: '20m',
    celeryHighQueueLengthThreshold: '100',
    celeryWorkerDownInterval: '15m',

    dashboardIds: {
      'celery-tasks-overview': 'celery-tasks-overview-32s3',
      'celery-tasks-by-task': 'celery-tasks-by-task-32s3',
    },
    dashboardUrls: {
      'celery-tasks-overview': '%s/d/%s/celery-tasks-overview' % [this.grafanaUrl, this.dashboardIds['celery-tasks-overview']],
      'celery-tasks-by-task': '%s/d/%s/celery-tasks-by-task' % [this.grafanaUrl, this.dashboardIds['celery-tasks-by-task']],
    },

    tags: ['celery', 'celery-mixin'],

    // Custom annotations to display in graphs
    annotation: {
      enabled: false,
      name: 'Custom Annotation',
      datasource: '-- Grafana --',
      iconColor: 'green',
      tags: [],
    },
  },
}
