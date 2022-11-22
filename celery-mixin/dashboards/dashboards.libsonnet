local grafana = import 'github.com/grafana/grafonnet-lib/grafonnet/grafana.libsonnet';
local template = grafana.template;
local statPanel = grafana.statPanel;
local row = grafana.row;
local prometheus = grafana.prometheus;

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
        current='',
        hide='',
        refresh=1,
        multi=true,
        includeAll=true,
        sort=1
      ),

    local taskFailed = |||
      sum by (name) (round(increase(celery_task_failed_total{%(celerySelector)s, name=~"$task"}[$__range]))) > 0
    ||| % $._config,
    local taskSucceeded = std.strReplace(taskFailed, 'failed', 'succeeded'),
    local taskReceived = std.strReplace(taskFailed, 'failed', 'received'),
    local taskRetried = std.strReplace(taskFailed, 'failed', 'retried'),
    local taskRevoked = std.strReplace(taskFailed, 'failed', 'revoked'),
    local taskRejected = std.strReplace(taskFailed, 'failed', 'rejected'),
    local taskSuccessRate = |||
      %s/(%s+%s) > -1
    ||| % [
      // Strip out > 0 from the end of the success query
      std.strReplace(taskSucceeded, ' > 0', ''),
      std.strReplace(taskSucceeded, ' > 0', ''),
      std.strReplace(taskFailed, ' > 0', ''),
    ],  // Add > -1 to remove NaN results

    local taskFailedInterval = |||
      sum by (name) (round(increase(celery_task_failed_total{%(celerySelector)s, name=~"$task"}[%(taskInterval)s])))
    ||| % $._config,
    local taskSucceededInterval = std.strReplace(taskFailedInterval, 'failed', 'succeeded'),
    local taskReceivedInterval = std.strReplace(taskFailedInterval, 'failed', 'received'),
    local taskRetriedInterval = std.strReplace(taskFailedInterval, 'failed', 'retried'),
    local taskRevokedInterval = std.strReplace(taskFailedInterval, 'failed', 'revoked'),
    local taskRejectedInterval = std.strReplace(taskFailedInterval, 'failed', 'rejected'),

    local taskRuntimeInterval = |||
      sum by (name) (rate(celery_task_runtime_sum{%(celerySelector)s, name=~"$task"}[%(taskInterval)s])) / sum by (name) (rate(celery_task_runtime_count{%(celerySelector)s, name=~"$task"}[%(taskInterval)s])) > 0
    ||| % $._config,

    local taskFailed1d = |||
      sum(round(increase(celery_task_failed_total{%(celerySelector)s}[1d])))
    ||| % $._config,
    local taskSucceeded1d = std.strReplace(taskFailed1d, 'failed', 'succeeded'),
    local taskReceived1d = std.strReplace(taskFailed1d, 'failed', 'received'),
    local taskSuccessRate1d = |||
      %s/(%s+%s)
    ||| % [taskSucceeded1d, taskSucceeded1d, taskFailed1d],
    local taskRuntime1d = |||
      sum(rate(celery_task_runtime_sum{%(celerySelector)s}[1d])) / sum(rate(celery_task_runtime_count{%(celerySelector)s}[1d])) > 0
    ||| % $._config,

    local topFailedTasks = |||
      round(topk(5, sum by (name) (increase(celery_task_failed_total{%(celerySelector)s}[1d]) > 0 )))
    ||| % $._config,

    local topTaskExceptions = |||
      round(topk(5, sum by (exception) (increase(celery_task_failed_total{%(celerySelector)s}[1d]) > 0 )))
    ||| % $._config,

    local topTaskRuntime = |||
      topk(5, (sum by(name) (rate(celery_task_runtime_sum{%(celerySelector)s}[1d])) / sum by (name) (rate(celery_task_runtime_count{%(celerySelector)s}[1d])) > 0 ))
    ||| % $._config,

    local summaryRow =
      row.new(
        title='Summary'
      ),

    local taskRow =
      row.new(
        title='Individual Tasks'
      ),

    'celery-tasks.json':
      grafana.dashboard.new(
        'Celery / Tasks',
        description='A dashboard that monitors Celery. It is created using the Celery-mixin for the the (Celery-exporter)[https://github.com/danihodovic/celery-exporter]',
        uid='celery-exporter',
        time_from='now-2d',
        time_to='now',
        timezone='utc'
      )
      .addPanel(summaryRow, gridPos={ h: 1, w: 24, x: 0, y: 0 })
      .addPanel(
        statPanel.new(
          'Celery Workers',
          datasource='$datasource',
          reducerFunction='last',
        )
        .addTarget(prometheus.target('count(celery_worker_up{%(celerySelector)s} == 1)' % $._config, intervalFactor=1)),
        gridPos={ h: 4, w: 4, x: 0, y: 1 }
      )
      .addPanel(
        statPanel.new(
          'Tasks Active',
          datasource='$datasource',
          reducerFunction='last',
        )
        .addTarget(prometheus.target('sum(celery_worker_tasks_active{%(celerySelector)s})' % $._config, intervalFactor=1)),
        gridPos={ h: 4, w: 5, x: 4, y: 1 }
      )
      .addPanel(
        statPanel.new(
          'Tasks received by workers last 24h',
          datasource='$datasource',
          reducerFunction='last'
        )
        .addTarget(prometheus.target(taskReceived1d)),
        gridPos={ h: 4, w: 5, x: 9, y: 1 }
      )
      .addPanel(
        statPanel.new(
          'Successful completion rate last 24h',
          datasource='$datasource',
          unit='percentunit',
          reducerFunction='last'
        )
        .addTarget(prometheus.target(taskSuccessRate1d))
        .addThreshold({ color: 'green', value: 0.95 }),
        gridPos={ h: 4, w: 5, x: 14, y: 1 }
      )
      .addPanel(
        statPanel.new(
          'Average Runtime for Tasks last 24h',
          datasource='$datasource',
          reducerFunction='last'
        )
        .addTarget(prometheus.target(taskRuntime1d)),
        gridPos={ h: 4, w: 5, x: 19, y: 1 }
      )
      .addPanel(
        grafana.tablePanel.new(
          'Top 5 failed tasks last 24h',
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
        .addTarget(prometheus.target(topFailedTasks, format='table', instant=true)),
        gridPos={ h: 8, w: 8, x: 0, y: 5 }
      )
      .addPanel(
        grafana.tablePanel.new(
          'Top 5 exceptions last 24h',
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
        .addTarget(prometheus.target(topTaskExceptions, format='table', instant=true)),
        gridPos={ h: 8, w: 8, x: 8, y: 5 }
      )
      .addPanel(
        grafana.tablePanel.new(
          'Top 5 task runtime last 24h',
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
        .addTarget(prometheus.target(topTaskRuntime, format='table', instant=true)),
        gridPos={ h: 8, w: 8, x: 16, y: 5 }
      )
      .addPanel(taskRow, gridPos={ h: 1, w: 24, x: 0, y: 13 })
      .addPanel(
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
              alias: 'Task',
              pattern: 'name',
            },
            {
              alias: 'Success Rate',
              pattern: 'Value #A',
              type: 'number',
              unit: 'percentunit',
            },
            {
              alias: 'Received',
              pattern: 'Value #B',
              type: 'number',
              unit: 'short',
              decimals: '0',
            },
            {
              alias: 'Succeeded',
              pattern: 'Value #C',
              type: 'number',
              unit: 'short',
              decimals: '0',
            },
            {
              alias: 'Failed',
              pattern: 'Value #D',
              type: 'number',
              unit: 'short',
              decimals: '0',
            },
            {
              alias: 'Rejected',
              pattern: 'Value #E',
              type: 'number',
              unit: 'short',
              decimals: '0',
            },
            {
              alias: 'Retried',
              pattern: 'Value #F',
              type: 'number',
              unit: 'short',
              decimals: '0',
            },
            {
              alias: 'Revoked',
              pattern: 'Value #G',
              type: 'number',
              unit: 'short',
              decimals: '0',
            },
          ]
        )
        .addTarget(prometheus.target(taskSuccessRate, format='table', instant=true))
        .addTarget(prometheus.target(taskReceived, format='table', instant=true))
        .addTarget(prometheus.target(taskSucceeded, format='table', instant=true))
        .addTarget(prometheus.target(taskFailed, format='table', instant=true))
        .addTarget(prometheus.target(taskRejected, format='table', instant=true))
        .addTarget(prometheus.target(taskRetried, format='table', instant=true))
        .addTarget(prometheus.target(taskRevoked, format='table', instant=true)),
        gridPos={ h: 8, w: 24, x: 0, y: 14 }
      )
      .addPanel(
        grafana.graphPanel.new(
          'Tasks completed with %(taskInterval)s intervals' % $._config,
          datasource='$datasource',
          legend_show=true,
          legend_values=true,
          legend_alignAsTable=true,
          legend_rightSide=true,
          legend_avg=true,
          legend_current=true,
          legend_hideZero=true,
        )
        .addTarget(prometheus.target(
          taskSucceededInterval,
          legendFormat='Succeeded - {{ name }}',
        ))
        .addTarget(prometheus.target(
          taskFailedInterval,
          legendFormat='Failed - {{ name }}',
        ))
        .addTarget(prometheus.target(
          taskReceivedInterval,
          legendFormat='Received - {{ name }}',
        ))
        .addTarget(prometheus.target(
          taskRetriedInterval,
          legendFormat='Retried - {{ name }}',
        ))
        .addTarget(prometheus.target(
          taskRejectedInterval,
          legendFormat='Rejected - {{ name }}',
        ))
        .addTarget(prometheus.target(
          taskRevokedInterval,
          legendFormat='Revoked - {{ name }}',
        )),
        gridPos={ h: 10, w: 24, x: 0, y: 22 },
      )
      .addPanel(
        grafana.graphPanel.new(
          'Tasks Runtime with %(taskInterval)s intervals' % $._config,
          datasource='$datasource',
          legend_show=true,
          legend_values=true,
          legend_alignAsTable=true,
          legend_rightSide=true,
          legend_avg=true,
          legend_current=true,
          legend_hideZero=true,
        )
        .addTarget(prometheus.target(
          taskRuntimeInterval,
          legendFormat='{{ name }}',
        )),
        gridPos={ h: 8, w: 24, x: 0, y: 32 },
      ) +
      { templating+: { list+: [prometheusTemplate, taskTemplate] } },
  },
}
