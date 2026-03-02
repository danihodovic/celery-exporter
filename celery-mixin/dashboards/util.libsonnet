local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';

local dashboard = g.dashboard;

local variable = dashboard.variable;
local datasource = variable.datasource;
local query = variable.query;

{
  filters(config):: {
    local this = self,
    cluster: '%(clusterLabel)s="$cluster"' % config,
    namespace: 'namespace="$namespace"',
    job: 'job=~"$job"',
    queueName: 'queue_name=~"$queue_name"',
    celeryIgnoredQueues: 'queue_name!~"%(celeryIgnoredQueues)s"' % config,
    taskV: 'name=~"$task"',
    celeryIgnoredTasks: 'name!~"%(celeryIgnoredTasks)s"' % config,

    // Django
    base: |||
      %(cluster)s,
      %(namespace)s,
      %(job)s
    ||| % this,

    default: |||
      %(cluster)s,
      %(namespace)s,
      %(job)s
    ||| % this,

    // default + ignored-queues exclusion, no $queue_name binding — for summary panels
    defaultQueue: |||
      %(base)s,
      %(celeryIgnoredQueues)s
    ||| % this,

    queue: |||
      %(base)s,
      %(queueName)s,
      %(celeryIgnoredQueues)s
    ||| % this,

    task: |||
      %(queue)s,
      %(taskV)s,
      %(celeryIgnoredTasks)s
    ||| % this,
  },

  variables(config):: {
    local this = self,

    local defaultFilters = $.filters(config),

    datasource:
      datasource.new(
        'datasource',
        'prometheus',
      ) +
      datasource.generalOptions.withLabel('Data source') +
      {
        current: {
          selected: true,
          text: config.datasourceName,
          value: config.datasourceName,
        },
      },

    cluster:
      query.new(
        config.clusterLabel,
        'label_values(celery_worker_up{}, cluster)',
      ) +
      query.withDatasourceFromVariable(this.datasource) +
      query.withSort() +
      query.generalOptions.withLabel('Cluster') +
      query.refresh.onLoad() +
      query.refresh.onTime() +
      (
        if config.showMultiCluster
        then query.generalOptions.showOnDashboard.withLabelAndValue()
        else query.generalOptions.showOnDashboard.withNothing()
      ),

    namespace:
      query.new(
        'namespace',
        'label_values(celery_worker_up{%(cluster)s}, namespace)' % defaultFilters
      ) +
      query.withDatasourceFromVariable(this.datasource) +
      query.withSort() +
      query.generalOptions.withLabel('Namespace') +
      query.selectionOptions.withMulti(false) +
      query.selectionOptions.withIncludeAll(false) +
      query.refresh.onLoad() +
      query.refresh.onTime(),

    job:
      query.new(
        'job',
        'label_values(celery_worker_up{%(cluster)s, %(namespace)s}, job)' % defaultFilters
      ) +
      query.withDatasourceFromVariable(this.datasource) +
      query.withSort() +
      query.generalOptions.withLabel('Job') +
      query.selectionOptions.withMulti(false) +
      query.selectionOptions.withIncludeAll(false) +
      query.refresh.onLoad() +
      query.refresh.onTime(),

    queueName:
      query.new(
        'queue_name',
        'label_values(celery_task_received_total{%(cluster)s, %(namespace)s, %(job)s, %(celeryIgnoredQueues)s}, queue_name)' % defaultFilters
      ) +
      query.withDatasourceFromVariable(this.datasource) +
      query.withSort() +
      query.generalOptions.withLabel('Queue Name') +
      query.selectionOptions.withMulti(true) +
      query.selectionOptions.withIncludeAll(true) +
      query.refresh.onLoad() +
      query.refresh.onTime(),

    task:
      query.new(
        'task',
        'label_values(celery_task_received_total{%(cluster)s, %(namespace)s, %(job)s, %(queueName)s, %(celeryIgnoredTasks)s}, name)' % defaultFilters
      ) +
      query.withDatasourceFromVariable(this.datasource) +
      query.withSort() +
      query.generalOptions.withLabel('Task') +
      query.selectionOptions.withMulti(true) +
      query.selectionOptions.withIncludeAll(false) +
      query.refresh.onLoad() +
      query.refresh.onTime(),
  },
}
