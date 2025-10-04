local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';
local dashboardUtil = import 'util.libsonnet';

local dashboard = g.dashboard;
local row = g.panel.row;
local grid = g.util.grid;

local timeSeriesPanel = g.panel.timeSeries;
local tablePanel = g.panel.table;
local statPanel = g.panel.stat;

// Stat
local stStandardOptions = statPanel.standardOptions;

// Timeseries
local tsStandardOptions = timeSeriesPanel.standardOptions;
local tsOverride = tsStandardOptions.override;

// Table
local tbPanelOptions = tablePanel.panelOptions;
local tbStandardOptions = tablePanel.standardOptions;
local tbQueryOptions = tablePanel.queryOptions;
local tbOverride = tbStandardOptions.override;

{
  local dashboardName = 'celery-tasks-overview',
  grafanaDashboards+:: {
    ['%s.json' % dashboardName]:

      local defaultVariables = dashboardUtil.variables($._config);

      local variables = [
        defaultVariables.datasource,
        defaultVariables.cluster,
        defaultVariables.namespace,
        defaultVariables.job,
        defaultVariables.queueName,
      ];

      local defaultFilters = dashboardUtil.filters($._config);
      local queries = {

        celeryWorkers: |||
          count(
            celery_worker_up{
              %(default)s
            } == 1
          )
        ||| % defaultFilters,

        celeryWorkersActive: |||
          sum(
            celery_worker_tasks_active{
              %(default)s
            }
          )
        ||| % defaultFilters,

        taskFailed1w: |||
          sum(
            round(
              increase(
                celery_task_failed_total{
                  %(queue)s
                }[1w]
              )
            )
          )
        ||| % defaultFilters,
        taskSucceeded1w: std.strReplace(queries.taskFailed1w, 'failed', 'succeeded'),
        tasksReceived1w: std.strReplace(queries.taskFailed1w, 'failed', 'received'),

        taskSuccessRate1w: |||
          %s/(%s+%s)
        ||| % [queries.taskSucceeded1w, queries.taskSucceeded1w, queries.taskFailed1w],

        taskRuntime1w: |||
          sum(
            rate(
              celery_task_runtime_sum{
                %(queue)s
              }[1w]
            )
          )
          /
          sum(
            rate(
              celery_task_runtime_count{
                %(queue)s
              }[1w]
            )
          ) > 0
        ||| % defaultFilters,

        tasksFailed1w: |||
          round(
            sum (
              increase(
                celery_task_failed_total{
                  %(queue)s
                }[1w]
              ) > 0
            )  by (job, name)
          )
        ||| % defaultFilters,

        topTaskExceptions1w: |||
          round(
            sum (
              increase(
                celery_task_failed_total{
                  %(queue)s
                }[1w]
              )
            ) by (job, exception) > 0
          )
        ||| % defaultFilters,

        topTaskRuntime1w: |||
          sum (
            rate(
              celery_task_runtime_sum{
                %(queue)s
              }[1w]
            )
          ) by(name)
          /
          sum (
            rate(
              celery_task_runtime_count{
                %(queue)s
              }[1w]
            )
          ) by (name) > 0
        ||| % defaultFilters,

        celeryQueueLength: |||
          sum (
            celery_queue_length{
              %(queue)s
            }
          ) by (job, queue_name)
        ||| % defaultFilters,

        taskFailed: |||
          sum (
            round(
              increase(
                celery_task_failed_total{
                  %(queue)s
                }[$__range]
              )
            )
          ) by (job) > 0
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


        taskFailedInterval: |||
          sum (
            round(
              increase(
                celery_task_failed_total{
                  %(queue)s
                }[$__rate_interval]
              )
            )
          )
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
                  %(queue)s
                }[$__rate_interval]
              ) > 0
            ) by (job, le)
          )
        ||| % defaultFilters,
        tasksRuntimeP95: std.strReplace(queries.tasksRuntimeP50, '0.50', '0.95'),
        tasksRuntimeP99: std.strReplace(queries.tasksRuntimeP50, '0.50', '0.99'),
      };

      local panels = {

        celeryWorkersStat:
          dashboardUtil.statPanel(
            'Workers',
            'short',
            queries.celeryWorkers,
            description='Number of active Celery Workers',
          ),

        celeryWorkersActiveStat:
          dashboardUtil.statPanel(
            'Workers Active Tasks',
            'short',
            queries.celeryWorkersActive,
            description='Number of active tasks across all workers',
          ),

        tasksReceivedByWorkers24hStat:
          dashboardUtil.statPanel(
            'Tasks received by workers [1w]',
            'short',
            queries.tasksReceived1w,
            description='Number of tasks received by workers in the last week',
          ),

        taskSuccessRate1wStat:
          dashboardUtil.statPanel(
            'Tasks Success Rate [1w]',
            'percentunit',
            queries.taskSuccessRate1w,
            description='Rate of successful tasks in the last week',
            steps=[
              stStandardOptions.threshold.step.withValue(0) +
              stStandardOptions.threshold.step.withColor('red'),
              stStandardOptions.threshold.step.withValue(0.95) +
              stStandardOptions.threshold.step.withColor('yellow'),
              stStandardOptions.threshold.step.withValue(0.99) +
              stStandardOptions.threshold.step.withColor('green'),
            ]
          ),

        taskRuntime1wStat:
          dashboardUtil.statPanel(
            'Average Runtime for Tasks [1w]',
            's',
            queries.taskRuntime1w,
            description='Average runtime for tasks in the last week',
          ),

        tasksFailed1wTable:
          dashboardUtil.tablePanel(
            'Top Failed Tasks [1w]',
            'short',
            queries.tasksFailed1w,
            description='Table of tasks with the most failures in the last week',
            sortBy={
              name: 'Value',
              desc: true,
            },
            transformations=[
              tbQueryOptions.transformation.withId(
                'organize'
              ) +
              tbQueryOptions.transformation.withOptions(
                {
                  renameByName: {
                    name: 'Task',
                  },
                  indexByName: {
                    name: 0,
                    Value: 1,
                  },
                  excludeByName: {
                    Time: true,
                    job: true,
                  },
                }
              ),
            ],
            overrides=[
              tbOverride.byName.new('Task') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withLinks(
                  tbPanelOptions.link.withTitle('Go To View') +
                  tbPanelOptions.link.withType('dashboard') +
                  tbPanelOptions.link.withUrl(
                    '/d/%s/celery-tasks-by-task?var-task=${__data.fields.Task}' % $._config.celeryTasksByTaskUid
                  ) +
                  tbPanelOptions.link.withTargetBlank(true)
                )
              ),
            ]
          ),

        taskExceptions1wTable:
          dashboardUtil.tablePanel(
            'Top Task Exceptions [1w]',
            'short',
            queries.topTaskExceptions1w,
            description='Table of the most common exceptions in the last week',
            sortBy={
              name: 'Value',
              desc: true,
            },
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
                    job: true,
                  },
                }
              ),
            ],
          ),

        tasksRuntime1wTable:
          dashboardUtil.tablePanel(
            'Top Average Task Runtime [1w]',
            's',
            queries.topTaskRuntime1w,
            description='Table of tasks with the highest average runtime in the last week',
            sortBy={
              name: 'Runtime',
              desc: true,
            },
            transformations=[
              tbQueryOptions.transformation.withId(
                'organize'
              ) +
              tbQueryOptions.transformation.withOptions(
                {
                  renameByName: {
                    name: 'Task',
                    Value: 'Runtime',
                  },
                  indexByName: {
                    name: 0,
                    Value: 1,
                  },
                  excludeByName: {
                    Time: true,
                  },
                }
              ),
            ],
            overrides=[
              tbOverride.byName.new('Task') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withLinks(
                  tbPanelOptions.link.withTitle('Go To Task') +
                  tbPanelOptions.link.withType('dashboard') +
                  tbPanelOptions.link.withUrl(
                    '/d/%s/celery-tasks-by-task?var-task=${__data.fields.Task}' % $._config.dashboardIds['celery-tasks-by-task']
                  ) +
                  tbPanelOptions.link.withTargetBlank(true)
                )
              ),
            ]
          ),

        celeryQueueLengthTimeSeries:
          dashboardUtil.timeSeriesPanel(
            'Queue Length',
            'short',
            queries.celeryQueueLength,
            '{{ job }}/{{ queue_name }}',
            description='Length of Celery queues',
            stack='normal'
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
            description='Table with an overview of task statistics',
            sortBy={
              name: 'Succeeded',
              desc: true,
            },
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
                    job: 'Job',
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
                    job: 0,
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
            ],
          ) +
          tbStandardOptions.withNoValue(0),

        tasksCompletedTimeSeries:
          dashboardUtil.timeSeriesPanel(
            'Tasks Completed',
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
            description='Number of tasks completed over time',
            stack='normal'
          ),

        tasksRuntimeTimeSeries:
          dashboardUtil.timeSeriesPanel(
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
              },
            ],
            description='Task runtime percentiles over time',
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
          row.new(
            'Summary'
          ) +
          row.gridPos.withX(0) +
          row.gridPos.withY(0) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        grid.wrapPanels(
          [
            panels.celeryWorkersStat,
            panels.celeryWorkersActiveStat,
            panels.tasksReceivedByWorkers24hStat,
            panels.taskSuccessRate1wStat,
          ],
          panelWidth=5,
          panelHeight=4,
          startY=1
        ) +
        [
          panels.taskRuntime1wStat +
          timeSeriesPanel.gridPos.withX(20) +
          timeSeriesPanel.gridPos.withY(1) +
          timeSeriesPanel.gridPos.withW(4) +
          timeSeriesPanel.gridPos.withH(4),
        ] +
        grid.wrapPanels(
          [
            panels.tasksFailed1wTable,
            panels.taskExceptions1wTable,
            panels.tasksRuntime1wTable,
          ],
          panelWidth=8,
          panelHeight=8,
          startY=5
        ) +
        [
          row.new(
            'Queues'
          ) +
          row.gridPos.withX(0) +
          row.gridPos.withY(13) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
          panels.celeryQueueLengthTimeSeries +
          timeSeriesPanel.gridPos.withX(0) +
          timeSeriesPanel.gridPos.withY(14) +
          timeSeriesPanel.gridPos.withW(24) +
          timeSeriesPanel.gridPos.withH(6),
        ] +
        [
          row.new(
            'Tasks'
          ) +
          row.gridPos.withX(0) +
          row.gridPos.withY(20) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
          panels.tasksStatsTable +
          tablePanel.gridPos.withX(0) +
          tablePanel.gridPos.withY(21) +
          tablePanel.gridPos.withW(24) +
          tablePanel.gridPos.withH(5),
          panels.tasksCompletedTimeSeries +
          timeSeriesPanel.gridPos.withX(0) +
          timeSeriesPanel.gridPos.withY(26) +
          timeSeriesPanel.gridPos.withW(24) +
          timeSeriesPanel.gridPos.withH(10),
          panels.tasksRuntimeTimeSeries +
          timeSeriesPanel.gridPos.withX(0) +
          timeSeriesPanel.gridPos.withY(36) +
          timeSeriesPanel.gridPos.withW(24) +
          timeSeriesPanel.gridPos.withH(10),
        ];

      dashboardUtil.bypassDashboardValidation +
      dashboard.new(
        'Celery / Tasks / Overview',
      ) +
      dashboard.withDescription(
        'A dashboard that monitors Celery. %s' % dashboardUtil.dashboardDescriptionLink
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
