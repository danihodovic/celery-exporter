local grafana = import 'github.com/grafana/grafonnet-lib/grafonnet/grafana.libsonnet';
local template = grafana.template;
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

    local taskTemplate =
      template.new(
        name='task',
        datasource='$datasource',
        query='label_values(celery_task_sent_total, name)',
        hide='',
        refresh=1,
        multi=true,
        includeAll=false,
        sort=1
      ),

    local taskExceptionsQuery = |||
      round(
        sum (
          increase(
            celery_task_failed_total{
              name=~"$task",
              %(celerySelector)s
            }[$__range]
          )
        ) by (name, exception) > 0
      )
    ||| % $._config,

    local taskExceptionsTable =
      grafana.tablePanel.new(
        'Task Exceptions',
        datasource='$datasource',
        span='4',
        sort={
          col: 3,
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
            alias: 'Exception',
            pattern: 'exception',
          },
        ]
      )
      .addTarget(
        prometheus.target(taskExceptionsQuery, format='table', instant=true)
      ) + paginateTable,

    local taskFailedQuery = |||
      sum (
        round(
          increase(
            celery_task_failed_total{
              name=~"$task",
              %(celerySelector)s,
            }[$__range]
          )
        )
      ) by (name) > 0
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
            decimals: '3',
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
              name=~"$task",
              %(celerySelector)s,
            }[$__rate_interval]
          )
        )
      ) by (name)
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
        legendFormat='Succeeded - {{ name }}',
      ))
      .addTarget(prometheus.target(
        taskFailedIntervalQuery,
        legendFormat='Failed - {{ name }}',
      ))
      .addTarget(prometheus.target(
        taskSentIntervalQuery,
        legendFormat='Sent - {{ name }}',
      ))
      .addTarget(prometheus.target(
        taskReceivedIntervalQuery,
        legendFormat='Received - {{ name }}',
      ))
      .addTarget(prometheus.target(
        taskRetriedIntervalQuery,
        legendFormat='Retried - {{ name }}',
      ))
      .addTarget(prometheus.target(
        taskRejectedIntervalQuery,
        legendFormat='Rejected - {{ name }}',
      ))
      .addTarget(prometheus.target(
        taskRevokedIntervalQuery,
        legendFormat='Revoked - {{ name }}',
      )),

    local tasksRuntimeP50Query = |||
      histogram_quantile(0.50,
        sum(
          irate(
            celery_task_runtime_bucket{
              name=~"$task",
              %(celerySelector)s
            }[$__rate_interval]
          ) > 0
        ) by (name, job, le)
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
          legendFormat='50 - {{ name }}',
        )
      )
      .addTarget(
        prometheus.target(
          tasksRuntimeP95Query,
          legendFormat='95 - {{ name }}',
        )
      )
      .addTarget(
        prometheus.target(
          tasksRuntimeP99Query,
          legendFormat='99 - {{ name }}',
        )
      )
      .addTarget(
        prometheus.target(
          tasksRuntimeP999Query,
          legendFormat='99.9 - {{ name }}',
        )
      ),

    local tasksRow =
      row.new(
        title='Tasks'
      ),

    'celery-tasks-by-task.json':
      grafana.dashboard.new(
        'Celery / Tasks / By Task',
        description='A dashboard that monitors Celery. It is created using the Celery-mixin for the the (Celery-exporter)[https://github.com/danihodovic/celery-exporter]',
        uid=$._config.celeryTasksByTaskUid,
        tags=$._config.tags,
        editable=true,
        time_from='now-2d',
        time_to='now',
        timezone='utc'
      )
      .addPanel(tasksRow, gridPos={ h: 1, w: 24, x: 0, y: 0 })
      .addPanel(
        tasksStatsTable,
        gridPos={ h: 8, w: 12, x: 0, y: 1 }
      )
      .addPanel(
        taskExceptionsTable,
        gridPos={ h: 8, w: 12, x: 12, y: 1 }
      )
      .addPanel(
        tasksCompletedGraphPanel,
        gridPos={ h: 10, w: 24, x: 0, y: 9 }
      )
      .addPanel(
        tasksRuntimeGraphPanel,
        gridPos={ h: 6, w: 24, x: 0, y: 19 }
      )
      +
      { templating+: { list+: [prometheusTemplate, taskTemplate] } } +
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
