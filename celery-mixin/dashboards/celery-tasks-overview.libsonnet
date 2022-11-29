local grafana = import 'github.com/grafana/grafonnet-lib/grafonnet/grafana.libsonnet';
local template = grafana.template;
local statPanel = grafana.statPanel;
local row = grafana.row;
local prometheus = grafana.prometheus;

local paginateTable = {
  pageSize: 6,
};

{
  grafanaDashboards+:: {

    local prometheusTemplate =
      template.datasource(
        'datasource',
        'prometheus',
        'Prometheus',
        hide='',
      ),

    local celeryWorkersQuery = |||
      count(
        celery_worker_up{
          %(celerySelector)s
        } == 1
      )
    ||| % $._config,
    local celeryWorkersStatPanel =
      statPanel.new(
        'Workers',
        datasource='$datasource',
        reducerFunction='last',
      )
      .addTarget(prometheus.target(celeryWorkersQuery))
      .addThresholds([
        { color: 'red', value: 0 },
        { color: 'green', value: 0.1 },
      ]),

    local celeryWorkersActiveQuery = |||
      sum(
        celery_worker_tasks_active{
          %(celerySelector)s
        }
      )
    ||| % $._config,
    local celeryWorkersActiveStatPanel =
      statPanel.new(
        'Tasks Active',
        datasource='$datasource',
        reducerFunction='last',
      )
      .addTarget(prometheus.target(celeryWorkersActiveQuery))
      .addThresholds([
        { color: 'red', value: 0 },
        { color: 'green', value: 0.1 },
      ]),

    local taskFailed1wQuery = |||
      sum(
        round(
          increase(
            celery_task_failed_total{
              %(celerySelector)s
            }[1w]
          )
        )
      )
    ||| % $._config,
    local taskSucceeded1wQuery = std.strReplace(taskFailed1wQuery, 'failed', 'succeeded'),

    local tasksReceived1wQuery = std.strReplace(taskFailed1wQuery, 'failed', 'received'),
    local tasksReceivedByWorkers24hStatPanel =
      statPanel.new(
        'Tasks received by workers [1w]',
        datasource='$datasource',
        reducerFunction='last',
      )
      .addTarget(prometheus.target(tasksReceived1wQuery))
      .addThresholds([
        { color: 'red', value: 0 },
        { color: 'green', value: 0.1 },
      ]),

    local taskSuccessRate1wQuery = |||
      %s/(%s+%s)
    ||| % [taskSucceeded1wQuery, taskSucceeded1wQuery, taskFailed1wQuery],
    local taskSuccessRate1wStatPanel =
      statPanel.new(
        'Tasks Success Rate [1w]',
        datasource='$datasource',
        unit='percentunit',
        reducerFunction='last',
      )
      .addTarget(prometheus.target(taskSuccessRate1wQuery))
      .addThresholds([
        { color: 'red', value: 0 },
        { color: 'yellow', value: 0.95 },
        { color: 'green', value: 0.99 },
      ]),

    local taskRuntime1wQuery = |||
      sum(
        rate(
          celery_task_runtime_sum{
            %(celerySelector)s
          }[1w]
        )
      )
      /
      sum(
        rate(
          celery_task_runtime_count{
            %(celerySelector)s
          }[1w]
        )
      ) > 0
    ||| % $._config,
    local taskRuntime1wStatPanel =
      statPanel.new(
        'Average Runtime for Tasks [1w]',
        datasource='$datasource',
        unit='s',
        reducerFunction='last',
      )
      .addTarget(prometheus.target(taskRuntime1wQuery))
      .addThresholds([
        { color: 'red', value: 0 },
        { color: 'green', value: 0.1 },
      ]),


    local tasksFailed1wQuery = |||
      round(
        sum (
          increase(
            celery_task_failed_total{
              %(celerySelector)s
            }[1w]
          ) > 0
        )  by (name)
      )
    ||| % $._config,

    local tasksFailed1wTable =
      grafana.tablePanel.new(
        'Top Failed Tasks [1w]',
        datasource='$datasource',
        span='4',
        sort={
          col: 2,
          desc: true,
        },
        styles=[
          {
            alias: 'Time',
            dateFormat: 'YYYY-MM-DD HH:mm:ss',
            type: 'hidden',
            pattern: 'Time',
          },
          {
            alias: 'Task',
            pattern: 'name',
          },
        ]
      )
      .addTarget(
        prometheus.target(tasksFailed1wQuery, format='table', instant=true)
      ) + paginateTable,


    local topTaskExceptions1wQuery = |||
      round(
        sum (
          increase(
            celery_task_failed_total{
              %(celerySelector)s
            }[1w]
          )
        ) by (exception) > 0
      )
    ||| % $._config,

    local taskExceptions1wTable =
      grafana.tablePanel.new(
        'Top Task Exceptions [1w]',
        datasource='$datasource',
        span='4',
        sort={
          col: 2,
          desc: true,
        },
        styles=[
          {
            alias: 'Time',
            dateFormat: 'YYYY-MM-DD HH:mm:ss',
            type: 'hidden',
            pattern: 'Time',
          },
          {
            alias: 'Exception',
            pattern: 'exception',
          },
        ]
      )
      .addTarget(
        prometheus.target(topTaskExceptions1wQuery, format='table', instant=true)
      ) + paginateTable,

    local topTaskRuntime1wQuery = |||
      sum (
        rate(
          celery_task_runtime_sum{
            %(celerySelector)s}[1w]
        )
      ) by(name)
      /
      sum (
        rate(
          celery_task_runtime_count{
            %(celerySelector)s
          }[1w]
        )
      ) by (name) > 0
    ||| % $._config,
    local tasksRuntime1wTable =
      grafana.tablePanel.new(
        'Top Average Task Runtime [1w]',
        datasource='$datasource',
        span='4',
        sort={
          col: 2,
          desc: true,
        },
        styles=[
          {
            alias: 'Time',
            dateFormat: 'YYYY-MM-DD HH:mm:ss',
            type: 'hidden',
            pattern: 'Time',
          },
          {
            alias: 'Task',
            pattern: 'name',
          },
          {
            alias: 'Runtime',
            pattern: 'Value',
            type: 'number',
            unit: 's',
          },
        ]
      )
      .addTarget(
        prometheus.target(topTaskRuntime1wQuery, format='table', instant=true)
      ) + paginateTable,

    local taskFailedQuery = |||
      sum (
        round(
          increase(
            celery_task_failed_total{
              %(celerySelector)s,
            }[$__range]
          )
        )
      ) by (job) > 0
    ||| % $._config,
    local taskSucceededQuery = std.strReplace(taskFailedQuery, 'failed', 'succeeded'),
    local taskSentQuery = std.strReplace(taskFailedQuery, 'failed', 'sent'),
    local taskReceivedQuery = std.strReplace(taskFailedQuery, 'failed', 'received'),
    local taskRetriedQuery = std.strReplace(taskFailedQuery, 'failed', 'retried'),
    local taskRevokedQuery = std.strReplace(taskFailedQuery, 'failed', 'revoked'),
    local taskRejectedQuery = std.strReplace(taskFailedQuery, 'failed', 'rejected'),
    local taskSuccessRateQuery = |||
      %s/(%s+%s) > -1
    ||| % [
      // Strip out > 0 from the end of the success query
      std.strReplace(taskSucceededQuery, ' > 0', ''),
      std.strReplace(taskSucceededQuery, ' > 0', ''),
      std.strReplace(taskFailedQuery, ' > 0', ''),
    ],  // Add > -1 to remove NaN results

    local tasksStatsTable =
      grafana.tablePanel.new(
        'Task Stats',
        datasource='$datasource',
        span='6',
        sort={
          col: 2,
          desc: false,
        },
        styles=[
          {
            alias: 'Time',
            dateFormat: 'YYYY-MM-DD HH:mm:ss',
            type: 'hidden',
            pattern: 'Time',
          },
          {
            alias: 'Job',
            type: 'hidden',
            pattern: 'job',
          },
          {
            alias: 'Success Rate',
            pattern: 'Value #A',
            type: 'number',
            unit: 'percentunit',
          },
          {
            alias: 'Suceeded',
            pattern: 'Value #B',
            type: 'number',
            unit: 'short',
            decimals: '0',
          },
          {
            alias: 'Failed',
            pattern: 'Value #C',
            type: 'number',
            unit: 'short',
            decimals: '0',
          },
          {
            alias: 'Sent',
            pattern: 'Value #D',
            type: 'number',
            unit: 'short',
            decimals: '0',
          },
          {
            alias: 'Received',
            pattern: 'Value #E',
            type: 'number',
            unit: 'short',
            decimals: '0',
          },
          {
            alias: 'Rejected',
            pattern: 'Value #F',
            type: 'number',
            unit: 'short',
            decimals: '0',
          },
          {
            alias: 'Retried',
            pattern: 'Value #G',
            type: 'number',
            unit: 'short',
            decimals: '0',
          },
          {
            alias: 'Revoked',
            pattern: 'Value #H',
            type: 'number',
            unit: 'short',
            decimals: '0',
          },
        ]
      )
      .addTarget(prometheus.target(taskSuccessRateQuery, format='table', instant=true))
      .addTarget(prometheus.target(taskSucceededQuery, format='table', instant=true))
      .addTarget(prometheus.target(taskFailedQuery, format='table', instant=true))
      .addTarget(prometheus.target(taskSentQuery, format='table', instant=true))
      .addTarget(prometheus.target(taskReceivedQuery, format='table', instant=true))
      .addTarget(prometheus.target(taskRejectedQuery, format='table', instant=true))
      .addTarget(prometheus.target(taskRetriedQuery, format='table', instant=true))
      .addTarget(prometheus.target(taskRevokedQuery, format='table', instant=true)),

    local taskFailedIntervalQuery = |||
      sum (
        round(
          increase(
            celery_task_failed_total{
              %(celerySelector)s,
            }[%(taskInterval)s]
          )
        )
      )
    ||| % $._config,
    local taskSucceededIntervalQuery = std.strReplace(taskFailedIntervalQuery, 'failed', 'succeeded'),
    local taskSentIntervalQuery = std.strReplace(taskFailedIntervalQuery, 'failed', 'sent'),
    local taskReceivedIntervalQuery = std.strReplace(taskFailedIntervalQuery, 'failed', 'received'),
    local taskRetriedIntervalQuery = std.strReplace(taskFailedIntervalQuery, 'failed', 'retried'),
    local taskRevokedIntervalQuery = std.strReplace(taskFailedIntervalQuery, 'failed', 'revoked'),
    local taskRejectedIntervalQuery = std.strReplace(taskFailedIntervalQuery, 'failed', 'rejected'),

    local tasksCompletedGraphPanel =
      grafana.graphPanel.new(
        'Tasks completed' % $._config,
        datasource='$datasource',
        legend_show=true,
        legend_values=true,
        legend_alignAsTable=true,
        legend_rightSide=true,
        legend_avg=true,
        legend_current=true,
        legend_hideZero=true,
        legend_sort='avg',
        legend_sortDesc=true,
        stack=true,
        fill=10,
        nullPointMode='null as zero'
      )
      .addTarget(prometheus.target(
        taskSucceededIntervalQuery,
        legendFormat='Succeeded',
      ))
      .addTarget(prometheus.target(
        taskFailedIntervalQuery,
        legendFormat='Failed',
      ))
      .addTarget(prometheus.target(
        taskSentIntervalQuery,
        legendFormat='Sent',
      ))
      .addTarget(prometheus.target(
        taskReceivedIntervalQuery,
        legendFormat='Received',
      ))
      .addTarget(prometheus.target(
        taskRetriedIntervalQuery,
        legendFormat='Retried',
      ))
      .addTarget(prometheus.target(
        taskRejectedIntervalQuery,
        legendFormat='Rejected',
      ))
      .addTarget(prometheus.target(
        taskRevokedIntervalQuery,
        legendFormat='Revoked',
      )),

    local tasksRuntimeP50Query = |||
      histogram_quantile(0.50,
        sum(
          irate(
            celery_task_runtime_bucket{
              %(celerySelector)s
            }[$__rate_interval]
          ) > 0
        ) by (job, le)
      )
    ||| % $._config,
    local tasksRuntimeP95Query = std.strReplace(tasksRuntimeP50Query, '0.50', '0.95'),
    local tasksRuntimeP99Query = std.strReplace(tasksRuntimeP50Query, '0.50', '0.99'),
    local tasksRuntimeP999Query = std.strReplace(tasksRuntimeP50Query, '0.50', '0.999'),

    local tasksRuntimeGraphPanel =
      grafana.graphPanel.new(
        'Tasks Runtime',
        datasource='$datasource',
        format='s',
        legend_show=true,
        legend_values=true,
        legend_alignAsTable=true,
        legend_rightSide=true,
        legend_avg=true,
        legend_current=true,
        legend_hideZero=true,
        nullPointMode='null as zero'
      )
      .addTarget(
        prometheus.target(
          tasksRuntimeP50Query,
          legendFormat='50',
        )
      )
      .addTarget(
        prometheus.target(
          tasksRuntimeP95Query,
          legendFormat='95',
        )
      )
      .addTarget(
        prometheus.target(
          tasksRuntimeP99Query,
          legendFormat='99',
        )
      )
      .addTarget(
        prometheus.target(
          tasksRuntimeP999Query,
          legendFormat='99.9',
        )
      ),

    local summaryRow =
      row.new(
        title='Summary'
      ),

    local tasksRow =
      row.new(
        title='Tasks'
      ),

    'celery-tasks-overview.json':
      grafana.dashboard.new(
        'Celery / Tasks / Overview',
        description='A dashboard that monitors Celery. It is created using the Celery-mixin for the the (Celery-exporter)[https://github.com/danihodovic/celery-exporter]',
        editable=true,
        uid=$._config.celeryTasksOverviewUid,
        tags=$._config.tags,
        time_from='now-2d',
        time_to='now',
        timezone='utc'
      )
      .addPanel(summaryRow, gridPos={ h: 1, w: 24, x: 0, y: 0 })
      .addPanel(
        celeryWorkersStatPanel,
        gridPos={ h: 4, w: 4, x: 0, y: 1 }
      )
      .addPanel(
        celeryWorkersActiveStatPanel,
        gridPos={ h: 4, w: 5, x: 4, y: 1 }
      )
      .addPanel(
        tasksReceivedByWorkers24hStatPanel,
        gridPos={ h: 4, w: 5, x: 9, y: 1 }
      )
      .addPanel(
        taskSuccessRate1wStatPanel,
        gridPos={ h: 4, w: 5, x: 14, y: 1 }
      )
      .addPanel(
        taskRuntime1wStatPanel,
        gridPos={ h: 4, w: 5, x: 19, y: 1 }
      )
      .addPanel(
        tasksFailed1wTable,
        gridPos={ h: 8, w: 8, x: 0, y: 5 }
      )
      .addPanel(
        taskExceptions1wTable,
        gridPos={ h: 8, w: 8, x: 8, y: 5 }
      )
      .addPanel(
        tasksRuntime1wTable,
        gridPos={ h: 8, w: 8, x: 16, y: 5 }
      )
      .addPanel(tasksRow, gridPos={ h: 1, w: 24, x: 0, y: 13 })
      .addPanel(
        tasksStatsTable,
        gridPos={ h: 4, w: 24, x: 0, y: 14 }
      )
      .addPanel(
        tasksCompletedGraphPanel,
        gridPos={ h: 10, w: 24, x: 0, y: 18 },
      )
      .addPanel(
        tasksRuntimeGraphPanel,
        gridPos={ h: 8, w: 24, x: 0, y: 28 },
      ) +
      { templating+: { list+: [prometheusTemplate] } } +
      if $._config.annotation.enabled then
        {
          annotations: {
            list: [
              $._config.customAnnotation,
            ],
          },
        }
      else {},
  },
}
