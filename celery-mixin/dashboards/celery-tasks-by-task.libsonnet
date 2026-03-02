local mixinUtils = import 'github.com/adinhodovic/mixin-utils/utils.libsonnet';
local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';
local dashboardUtil = import 'util.libsonnet';

local dashboard = g.dashboard;
local row = g.panel.row;
local grid = g.util.grid;

local timeSeriesPanel = g.panel.timeSeries;
local tablePanel = g.panel.table;

// Timeseries
local tsStandardOptions = timeSeriesPanel.standardOptions;
local tsOverride = tsStandardOptions.override;

// Table
local tbStandardOptions = tablePanel.standardOptions;
local tbQueryOptions = tablePanel.queryOptions;
local tbOverride = tbStandardOptions.override;

{
  local dashboardName = 'celery-tasks-by-task',
  grafanaDashboards+:: {
    ['%s.json' % dashboardName]:

      local defaultVariables = dashboardUtil.variables($._config);

      local variables = [
        defaultVariables.datasource,
        defaultVariables.cluster,
        defaultVariables.namespace,
        defaultVariables.job,
        defaultVariables.queueName,
        defaultVariables.task,
      ];

      local defaultFilters = dashboardUtil.filters($._config);
      local queries = {

        // 1w stats table queries — filtered by task
        taskExceptions: |||
          round(
            sum(
              increase(
                celery_task_failed_total{
                  %(task)s
                }[1w]
              )
            ) by (name, exception)
          )
        ||| % defaultFilters,

        taskFailed: |||
          sum(
            round(
              increase(
                celery_task_failed_total{
                  %(task)s
                }[1w]
              )
            )
          ) by (name)
        ||| % defaultFilters,
        taskSucceeded: std.strReplace(queries.taskFailed, 'failed', 'succeeded'),
        taskSent: std.strReplace(queries.taskFailed, 'failed', 'sent'),
        taskReceived: std.strReplace(queries.taskFailed, 'failed', 'received'),
        taskRetried: std.strReplace(queries.taskFailed, 'failed', 'retried'),
        taskRevoked: std.strReplace(queries.taskFailed, 'failed', 'revoked'),
        taskRejected: std.strReplace(queries.taskFailed, 'failed', 'rejected'),
        taskSuccessRate: |||
          %s/(%s+%s) > -1
        ||| % [
          queries.taskSucceeded,
          queries.taskSucceeded,
          queries.taskFailed,
        ],  // > -1 removes NaN results from division by zero when no tasks ran

        // Interval time series queries — filtered by task
        taskFailedByExceptionInterval: |||
          sum(
            round(
              increase(
                celery_task_failed_total{
                  %(task)s
                }[$__rate_interval]
              )
            )
          ) by (name, exception)
        ||| % defaultFilters,

        taskFailedInterval: |||
          sum(
            round(
              increase(
                celery_task_failed_total{
                  %(task)s
                }[$__rate_interval]
              )
            )
          ) by (name)
        ||| % defaultFilters,
        taskSucceededInterval: std.strReplace(queries.taskFailedInterval, 'failed', 'succeeded'),
        taskSentInterval: std.strReplace(queries.taskFailedInterval, 'failed', 'sent'),
        taskReceivedInterval: std.strReplace(queries.taskFailedInterval, 'failed', 'received'),
        taskRetriedInterval: std.strReplace(queries.taskFailedInterval, 'failed', 'retried'),
        taskRevokedInterval: std.strReplace(queries.taskFailedInterval, 'failed', 'revoked'),
        taskRejectedInterval: std.strReplace(queries.taskFailedInterval, 'failed', 'rejected'),

        taskSuccessRateInterval: |||
          sum(
            rate(
              celery_task_succeeded_total{
                %(task)s
              }[$__rate_interval]
            )
          )
          /
          (
            sum(
              rate(
                celery_task_succeeded_total{
                  %(task)s
                }[$__rate_interval]
              )
            )
            +
            sum(
              rate(
                celery_task_failed_total{
                  %(task)s
                }[$__rate_interval]
              )
            )
          )
        ||| % defaultFilters,

        tasksRuntimeP50: |||
          histogram_quantile(0.50,
            sum(
              irate(
                celery_task_runtime_bucket{
                  %(task)s
                }[$__rate_interval]
              )
            ) by (name, job, le)
          )
        ||| % defaultFilters,
        tasksRuntimeP95: std.strReplace(queries.tasksRuntimeP50, '0.50', '0.95'),
        tasksRuntimeP99: std.strReplace(queries.tasksRuntimeP50, '0.50', '0.99'),

        // Pie chart queries — 6h fixed window, no task filter (queue-level overview)
        taskRateByQueue6h: |||
          topk(10,
            sum(
              rate(
                celery_task_received_total{
                  %(queue)s
                }[6h]
              )
            ) by (queue_name)
          )
        ||| % defaultFilters,

        taskRateByName6h: |||
          topk(10,
            sum(
              rate(
                celery_task_received_total{
                  %(queue)s
                }[6h]
              )
            ) by (name)
          )
        ||| % defaultFilters,

        taskSucceeded6hPie: |||
          sum(
            increase(
              celery_task_succeeded_total{
                %(queue)s
              }[6h]
            )
          )
        ||| % defaultFilters,
        taskFailed6hPie: |||
          sum(
            increase(
              celery_task_failed_total{
                %(queue)s
              }[6h]
            )
          )
        ||| % defaultFilters,

        taskSent6h: |||
          sum(
            increase(
              celery_task_sent_total{
                %(queue)s
              }[6h]
            )
          )
        ||| % defaultFilters,
        taskReceived6h: |||
          sum(
            increase(
              celery_task_received_total{
                %(queue)s
              }[6h]
            )
          )
        ||| % defaultFilters,
        taskRetried6h: |||
          sum(
            increase(
              celery_task_retried_total{
                %(queue)s
              }[6h]
            )
          )
        ||| % defaultFilters,
        taskRevoked6h: |||
          sum(
            increase(
              celery_task_revoked_total{
                %(queue)s
              }[6h]
            )
          )
        ||| % defaultFilters,
        taskRejected6h: |||
          sum(
            increase(
              celery_task_rejected_total{
                %(queue)s
              }[6h]
            )
          )
        ||| % defaultFilters,
      };

      local panels = {

        // Summary pie charts — queue-level, no task filter
        taskRateByQueuePieChart:
          mixinUtils.dashboards.pieChartPanel(
            'Task Rate by Queue [6h]',
            'reqps',
            queries.taskRateByQueue6h,
            '{{ queue_name }}',
            description='Distribution of task throughput across queues over the past 6 hours (top 10). Shows which queues are handling the most work. Not filtered by selected task — use as a queue-level context panel.',
          ),

        taskRateByNamePieChart:
          mixinUtils.dashboards.pieChartPanel(
            'Task Rate by Name [6h]',
            'reqps',
            queries.taskRateByName6h,
            '{{ name }}',
            description='Distribution of task throughput by task name over the past 6 hours (top 10). Shows which tasks run most frequently in this queue. Not filtered by selected task — use as a queue-level context panel.',
          ),

        taskSuccessVsFailurePieChart:
          mixinUtils.dashboards.pieChartPanel(
            'Task Success vs Failure [6h]',
            'short',
            [
              {
                expr: queries.taskSucceeded6hPie,
                legend: 'Succeeded',
              },
              {
                expr: queries.taskFailed6hPie,
                legend: 'Failed',
              },
            ],
            description='Queue-level health split between succeeded and failed tasks over the past 6 hours. Not filtered by selected task — provides broader context for the queue.',
          ),

        taskStatesPieChart:
          mixinUtils.dashboards.pieChartPanel(
            'Task States [6h]',
            'short',
            [
              {
                expr: queries.taskSent6h,
                legend: 'Sent',
              },
              {
                expr: queries.taskReceived6h,
                legend: 'Received',
              },
              {
                expr: queries.taskSucceeded6hPie,
                legend: 'Succeeded',
              },
              {
                expr: queries.taskFailed6hPie,
                legend: 'Failed',
              },
              {
                expr: queries.taskRetried6h,
                legend: 'Retried',
              },
              {
                expr: queries.taskRevoked6h,
                legend: 'Revoked',
              },
              {
                expr: queries.taskRejected6h,
                legend: 'Rejected',
              },
            ],
            description='Queue-level distribution of all task lifecycle states over the past 6 hours. Not filtered by selected task — provides broader context for the queue.',
          ),

        tasksStatsTable:
          mixinUtils.dashboards.tablePanel(
            'Task Stats [1w]',
            'short',
            [
              {
                expr: queries.taskSuccessRate,
              },
              {
                expr: queries.taskSucceeded,
              },
              {
                expr: queries.taskFailed,
              },
              {
                expr: queries.taskSent,
              },
              {
                expr: queries.taskReceived,
              },
              {
                expr: queries.taskRejected,
              },
              {
                expr: queries.taskRetried,
              },
              {
                expr: queries.taskRevoked,
              },
            ],
            sortBy={
              name: 'Succeeded',
              desc: true,
            },
            description='A table of task statistics including success rate, succeeded, failed, sent, received, rejected, retried and revoked tasks grouped by task name over the last week.',
            transformations=[
              tbQueryOptions.transformation.withId(
                'merge'
              ),
              tbQueryOptions.transformation.withId(
                'organize'
              ) +
              tbQueryOptions.transformation.withOptions(
                {
                  renameByName: {
                    'Value #A': 'Success Rate',
                    'Value #B': 'Succeeded',
                    'Value #C': 'Failed',
                    'Value #D': 'Sent',
                    'Value #E': 'Received',
                    'Value #F': 'Rejected',
                    'Value #G': 'Retried',
                    'Value #H': 'Revoked',
                  },
                  indexByName: {
                    'Value #A': 0,
                    'Value #B': 1,
                    'Value #C': 2,
                    'Value #D': 3,
                    'Value #E': 4,
                    'Value #F': 5,
                    'Value #G': 6,
                    'Value #H': 7,
                  },
                  excludeByName: {
                    Time: true,
                    name: true,
                  },
                }
              ),
            ],
            overrides=[
              tbOverride.byName.new('Success Rate') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('percentunit')
              ),
            ]
          ) +
          tbStandardOptions.withNoValue(0),

        taskEventsTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'Task Events',
            'short',
            [
              {
                expr: queries.taskSucceededInterval,
                legend: 'Succeeded',
              },
              {
                expr: queries.taskFailedInterval,
                legend: 'Failed',
              },
              {
                expr: queries.taskSentInterval,
                legend: 'Sent',
              },
              {
                expr: queries.taskReceivedInterval,
                legend: 'Received',
              },
              {
                expr: queries.taskRetriedInterval,
                legend: 'Retried',
              },
              {
                expr: queries.taskRevokedInterval,
                legend: 'Revoked',
              },
              {
                expr: queries.taskRejectedInterval,
                legend: 'Rejected',
              },
            ],
            description='Task lifecycle event counts over time including succeeded, failed, sent, received, rejected, retried and revoked.',
            stack='normal'
          ),

        taskSuccessRateTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'Task Success Rate',
            'percentunit',
            queries.taskSuccessRateInterval,
            'Success Rate',
            description='Task success rate over time computed as succeeded / (succeeded + failed). Drops indicate periods of elevated failures.',
            min=0,
            max=1,
            stack='normal',
          ),

        tasksRuntimeTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'Tasks Runtime',
            's',
            [
              {
                expr: queries.tasksRuntimeP50,
                legend: 'P50',
              },
              {
                expr: queries.tasksRuntimeP95,
                legend: 'P95',
              },
              {
                expr: queries.tasksRuntimeP99,
                legend: 'P99',
                exemplar: true,
              },
            ],
            description='Task runtime percentiles (P50, P95, P99). Exemplars on P99 link to distributed traces for root cause analysis.',
            overrides=[
              tsOverride.byName.new('P50') +
              tsOverride.byName.withPropertiesFromOptions(
                tsStandardOptions.color.withMode('fixed') +
                tsStandardOptions.color.withFixedColor('green')
              ),
              tsOverride.byName.new('P95') +
              tsOverride.byName.withPropertiesFromOptions(
                tsStandardOptions.color.withMode('fixed') +
                tsStandardOptions.color.withFixedColor('yellow')
              ),
              tsOverride.byName.new('P99') +
              tsOverride.byName.withPropertiesFromOptions(
                tsStandardOptions.color.withMode('fixed') +
                tsStandardOptions.color.withFixedColor('red')
              ),
            ]
          ),

        taskExceptionsByTypeTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'Task Exceptions by Type',
            'short',
            queries.taskFailedByExceptionInterval,
            '{{ exception }}',
            description='Task failure rate over time broken down by exception type. Helps identify recurring or new exception classes causing task failures.',
            stack='normal',
          ),

        taskExceptionsTable:
          mixinUtils.dashboards.tablePanel(
            'Task Exceptions [1w]',
            'short',
            queries.taskExceptions,
            sortBy={
              name: 'Value',
              desc: true,
            },
            description='Task exceptions grouped by task name and exception type over the last week.',
            transformations=[
              tbQueryOptions.transformation.withId(
                'organize'
              ) +
              tbQueryOptions.transformation.withOptions(
                {
                  renameByName: {
                    exception: 'Exception',
                  },
                  indexByName: {
                    exception: 0,
                    Value: 1,
                  },
                  excludeByName: {
                    Time: true,
                    name: true,
                    job: true,
                  },
                }
              ),
            ]
          ),
      };

      local rows =
        [
          row.new('Summary') +
          row.gridPos.withX(0) +
          row.gridPos.withY(0) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        grid.wrapPanels(
          [
            panels.taskRateByQueuePieChart,
            panels.taskRateByNamePieChart,
            panels.taskSuccessVsFailurePieChart,
            panels.taskStatesPieChart,
          ],
          panelWidth=6,
          panelHeight=5,
          startY=1
        ) +
        [
          row.new('$task') +
          row.gridPos.withX(0) +
          row.gridPos.withY(6) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1) +
          row.withRepeat('task'),
        ] +
        [
          panels.tasksStatsTable +
          tablePanel.gridPos.withX(0) +
          tablePanel.gridPos.withY(7) +
          tablePanel.gridPos.withW(14) +
          tablePanel.gridPos.withH(7),
          panels.taskExceptionsTable +
          tablePanel.gridPos.withX(14) +
          tablePanel.gridPos.withY(7) +
          tablePanel.gridPos.withW(10) +
          tablePanel.gridPos.withH(7),
        ] +
        grid.wrapPanels(
          [
            panels.taskEventsTimeSeries,
            panels.taskExceptionsByTypeTimeSeries,
            panels.taskSuccessRateTimeSeries,
            panels.tasksRuntimeTimeSeries,
          ],
          panelWidth=12,
          panelHeight=6,
          startY=14
        );

      mixinUtils.dashboards.bypassDashboardValidation +
      dashboard.new('Celery / Tasks / By Task') +
      dashboard.withDescription('A dashboard to monitor Celery tasks grouped by task name. %s' % mixinUtils.dashboards.dashboardDescriptionLink('celery-exporter', 'https://github.com/danihodovic/celery-exporter')) +
      dashboard.withUid($._config.dashboardIds[dashboardName]) +
      dashboard.withTags($._config.tags) +
      dashboard.withTimezone('utc') +
      dashboard.withEditable(false) +
      dashboard.time.withFrom('now-1d') +
      dashboard.time.withTo('now') +
      dashboard.withVariables(variables) +
      dashboard.withLinks(
        mixinUtils.dashboards.dashboardLinks('Celery', $._config)
      ) +
      dashboard.withPanels(
        rows
      ) +
      dashboard.withAnnotations(
        mixinUtils.dashboards.annotations($._config, defaultFilters)
      ),
  },
}
