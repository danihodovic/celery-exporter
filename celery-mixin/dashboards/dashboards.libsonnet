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
        includeAll=false,
        sort=1
      ),

    local taskFailed = |||
      sum by (name) (increase(celery_task_failed_total{%(celerySelector)s, name=~"$task"}[$__range]))
    ||| % $._config,
    local taskSucceeded = std.strReplace(taskFailed, 'failed', 'succeeded'),
    local taskReceived = std.strReplace(taskFailed, 'failed', 'received'),
    local taskRetried = std.strReplace(taskFailed, 'failed', 'retried'),
    local taskRevoked = std.strReplace(taskFailed, 'failed', 'revoked'),
    local taskRejected = std.strReplace(taskFailed, 'failed', 'rejected'),
    local taskSuccessRate = |||
      %s/(%s+%s)
    ||| % [taskSucceeded, taskSucceeded, taskFailed],

    local taskFailedInterval = |||
      sum by (name) (increase(celery_task_failed_total{%(celerySelector)s, name=~"$task"}[%(taskInterval)s]))
    ||| % $._config,
    local taskSucceededInterval = std.strReplace(taskFailedInterval, 'failed', 'succeeded'),
    local taskReceivedInterval = std.strReplace(taskFailedInterval, 'failed', 'received'),
    local taskRetriedInterval = std.strReplace(taskFailedInterval, 'failed', 'retried'),
    local taskRevokedInterval = std.strReplace(taskFailedInterval, 'failed', 'revoked'),
    local taskRejectedInterval = std.strReplace(taskFailedInterval, 'failed', 'rejected'),

    local taskFailed1d = |||
      sum(increase(celery_task_failed_total{%(celerySelector)s}[1d]))
    ||| % $._config,
    local taskSucceeded1d = std.strReplace(taskFailed1d, 'failed', 'succeeded'),
    local taskReceived1d = std.strReplace(taskFailed1d, 'failed', 'received'),
    local taskSuccessRate1d = |||
      %s/(%s+%s)
    ||| % [taskSucceeded1d, taskSucceeded1d, taskFailed1d],

    local summaryRow =
      row.new(
        title='Summary'
      ),

    local taskRow =
      row.new(
        title='Individual Tasks'
      ),

    'celery.json':
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
          reducerFunction='last'
        )
        .addTarget(prometheus.target('count(celery_worker_up)')),
        gridPos={ h: 4, w: 6, x: 0, y: 1 }
      )
      .addPanel(
        statPanel.new(
          'Tasks Active',
          datasource='$datasource',
          reducerFunction='last'
        )
        .addTarget(prometheus.target('sum(celery_worker_tasks_active)')),
        gridPos={ h: 4, w: 6, x: 6, y: 1 }
      )
      .addPanel(
        statPanel.new(
          'Tasks received by workers last 24h',
          datasource='$datasource',
          reducerFunction='last'
        )
        .addTarget(prometheus.target(taskReceived1d)),
        gridPos={ h: 4, w: 6, x: 12, y: 1 }
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
        gridPos={ h: 4, w: 6, x: 18, y: 1 }
      )
      .addPanel(taskRow, gridPos={ h: 1, w: 24, x: 0, y: 5 })
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
              alias: 'Succeeded',
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
              alias: 'Rejected',
              pattern: 'Value #D',
              type: 'number',
              unit: 'short',
              decimals: '0',
            },
            {
              alias: 'Retried',
              pattern: 'Value #E',
              type: 'number',
              unit: 'short',
              decimals: '0',
            },
            {
              alias: 'Revoked',
              pattern: 'Value #F',
              type: 'number',
              unit: 'short',
              decimals: '0',
            },
          ]
        )
        .addTarget(prometheus.target(taskSuccessRate, format='table', instant=true))
        .addTarget(prometheus.target(taskSucceeded, format='table', instant=true))
        .addTarget(prometheus.target(taskFailed, format='table', instant=true))
        .addTarget(prometheus.target(taskRejected, format='table', instant=true))
        .addTarget(prometheus.target(taskRetried, format='table', instant=true))
        .addTarget(prometheus.target(taskRevoked, format='table', instant=true)),
        gridPos={ h: 6, w: 24, x: 0, y: 6 }
      )
      .addPanel(
        grafana.graphPanel.new(
          'Tasks completed with %(taskInterval)s intervals' % $._config,
          legend_show=true,
          legend_values=true,
          legend_alignAsTable=true,
          legend_rightSide=true,
          legend_avg=true,
          legend_max=true,
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
        gridPos={ h: 10, w: 24, x: 0, y: 12 },
      ) +
      { templating+: { list+: [prometheusTemplate, taskTemplate] } },
  },
}
