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

        taskExceptions: |||
          round(
            sum (
              increase(
                celery_task_failed_total{
                  %(task)s
                }[$__range]
              )
            ) by (name, exception) > 0
          )
        ||| % defaultFilters,

        taskFailed: |||
          sum (
            round(
              increase(
                celery_task_failed_total{
                  %(task)s
                }[$__range]
              )
            )
          ) by (name) > 0
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
          // Strip out > 0 from the end of the success query
          std.strReplace(queries.taskSucceeded, ' > 0', ''),
          std.strReplace(queries.taskSucceeded, ' > 0', ''),
          std.strReplace(queries.taskFailed, ' > 0', ''),
        ],  // Add > -1 to remove NaN results

        taskFailedByExceptionInterval: |||
          sum (
            round(
              increase(
                celery_task_failed_total{
                  %(task)s
                }[$__rate_interval]
              )
            )
          ) by (name, exception) > 0
        ||| % defaultFilters,

        taskFailedInterval: |||
          sum (
            round(
              increase(
                celery_task_failed_total{
                  %(task)s
                }[$__rate_interval]
              )
            )
          ) by (name) > 0
        ||| % defaultFilters,
        taskSucceededInterval: std.strReplace(queries.taskFailedInterval, 'failed', 'succeeded'),
        taskSentInterval: std.strReplace(queries.taskFailedInterval, 'failed', 'sent'),
        taskReceivedInterval: std.strReplace(queries.taskFailedInterval, 'failed', 'received'),
        taskRetriedInterval: std.strReplace(queries.taskFailedInterval, 'failed', 'retried'),
        taskRevokedInterval: std.strReplace(queries.taskFailedInterval, 'failed', 'revoked'),
        taskRejectedInterval: std.strReplace(queries.taskFailedInterval, 'failed', 'rejected'),

        tasksRuntimeP50: |||
          histogram_quantile(0.50,
            sum(
              irate(
                celery_task_runtime_bucket{
                  %(task)s
                }[$__rate_interval]
              ) > 0
            ) by (name, job, le)
          )
        ||| % defaultFilters,
        tasksRuntimeP95: std.strReplace(queries.tasksRuntimeP50, '0.50', '0.95'),
        tasksRuntimeP99: std.strReplace(queries.tasksRuntimeP50, '0.50', '0.99'),
      };

      local panels = {

        taskExceptionsTable:
          dashboardUtil.tablePanel(
            'Task Exceptions',
            'short',
            queries.taskExceptions,
            sortBy={
              name: 'Value',
              desc: true,
            },
            description='A table of task exceptions grouped by task name and exception type.',
            transformations=[
              tbQueryOptions.transformation.withId(
                'organize'
              ) +
              tbQueryOptions.transformation.withOptions(
                {
                  renameByName: {
                    name: 'Task',
                    exception: 'Exception',
                  },
                  indexByName: {
                    name: 0,
                    exception: 1,
                    Value: 2,
                  },
                  excludeByName: {
                    Time: true,
                    job: true,
                  },
                }
              ),
            ]
          ),

        tasksStatsTable:
          dashboardUtil.tablePanel(
            'Task Stats',
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
            description='A table of task statistics including success rate, succeeded, failed, sent, received, rejected, retried and revoked tasks grouped by task name.',
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
                    name: 'Name',
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
                    name: 0,
                    'Value #A': 1,
                    'Value #B': 2,
                    'Value #C': 3,
                    'Value #D': 4,
                    'Value #E': 5,
                    'Value #F': 6,
                    'Value #G': 7,
                    'Value #H': 8,
                  },
                  excludeByName: {
                    Time: true,
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

        tasksFailedByExceptionTimeSeries:
          dashboardUtil.timeSeriesPanel(
            'Task Exceptions',
            'short',
            queries.taskFailedByExceptionInterval,
            '{{ name }}/{{ exception }}',
            description='A time series of task exceptions grouped by task name and exception type.',
            stack='normal'
          ),

        tasksCompletedTimeSeries:
          dashboardUtil.timeSeriesPanel(
            'Tasks Completed',
            'short',
            [
              {
                expr: queries.taskSucceededInterval,
                legend: 'Succeeded - {{ name }}',
              },
              {
                expr: queries.taskFailedInterval,
                legend: 'Failed - {{ name }}',
              },
              {
                expr: queries.taskSentInterval,
                legend: 'Sent - {{ name }}',
              },
              {
                expr: queries.taskReceivedInterval,
                legend: 'Received - {{ name }}',
              },
              {
                expr: queries.taskRetriedInterval,
                legend: 'Retried - {{ name }}',
              },
              {
                expr: queries.taskRevokedInterval,
                legend: 'Revoked - {{ name }}',
              },
              {
                expr: queries.taskRejectedInterval,
                legend: 'Rejected - {{ name }}',
              },
            ],
            description='A time series of tasks completed including succeeded, failed, sent, received, rejected, retried and revoked tasks grouped by task name.',
            stack='normal'
          ),

        tasksRuntimeTimeSeries:
          dashboardUtil.timeSeriesPanel(
            'Tasks Runtime',
            's',
            [
              {
                expr: queries.tasksRuntimeP50,
                legend: 'P50 - {{ name }}',
              },
              {
                expr: queries.tasksRuntimeP95,
                legend: 'P95 - {{ name }}',
              },
              {
                expr: queries.tasksRuntimeP99,
                legend: 'P99 - {{ name }}',
              },
            ],
            description='A time series of task runtime percentiles (P50, P95, P99) grouped by task name.',
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
            panels.tasksStatsTable,
            panels.taskExceptionsTable,
          ],
          panelWidth=24,
          panelHeight=8,
          startY=1
        ) +
        [
          row.new('Tasks') +
          row.gridPos.withX(0) +
          row.gridPos.withY(17) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        grid.wrapPanels(
          [
            panels.tasksCompletedTimeSeries,
            panels.tasksFailedByExceptionTimeSeries,
            panels.tasksRuntimeTimeSeries,
          ],
          panelWidth=24,
          panelHeight=6,
          startY=18
        );

      dashboardUtil.bypassDashboardValidation +
      dashboard.new('Celery / Tasks / By Task') +
      dashboard.withDescription(
        'A dashboard to monitor Celery tasks grouped by task name. %s' % dashboardUtil.dashboardDescriptionLink
      ) +
      dashboard.withUid($._config.dashboardIds[dashboardName]) +
      dashboard.withTags($._config.tags) +
      dashboard.withTimezone('utc') +
      dashboard.withEditable(false) +
      dashboard.time.withFrom('now-2d') +
      dashboard.time.withTo('now') +
      dashboard.withVariables(variables) +
      dashboard.withLinks(
        dashboardUtil.dashboardLinks($._config)
      ) +
      dashboard.withPanels(
        rows
      ) +
      dashboard.withAnnotations(
        dashboardUtil.annotations($._config, defaultFilters)
      ),
  },
}
