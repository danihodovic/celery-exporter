local mixinUtils = import 'github.com/adinhodovic/mixin-utils/utils.libsonnet';
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
              %(defaultQueue)s
            } == 1
          )
        ||| % defaultFilters,

        celeryWorkersActive: |||
          sum(
            celery_worker_tasks_active{
              %(defaultQueue)s
            }
          )
        ||| % defaultFilters,

        queueCount: |||
          count(
            group by (queue_name) (
              celery_queue_length{
                %(defaultQueue)s
              }
            )
          )
        ||| % defaultFilters,

        taskFailed1w: |||
          sum(
            round(
              increase(
                celery_task_failed_total{
                  %(defaultQueue)s
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
                %(defaultQueue)s
              }[1w]
            )
          )
          /
          sum(
            rate(
              celery_task_runtime_count{
                %(defaultQueue)s
              }[1w]
            )
          ) > 0
        ||| % defaultFilters,

        tasksFailed1w: |||
          round(
            sum(
              increase(
                celery_task_failed_total{
                  %(queue)s
                }[1w]
              )
            ) by (job, name)
          )
        ||| % defaultFilters,

        topTaskExceptions1w: |||
          round(
            sum(
              increase(
                celery_task_failed_total{
                  %(queue)s
                }[1w]
              )
            ) by (job, exception)
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
          sum(
            round(
              increase(
                celery_task_failed_total{
                  %(queue)s
                }[$__range]
              )
            )
          ) by (job)
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


        taskFailedInterval: |||
          sum(
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
              )
            ) by (job, le)
          )
        ||| % defaultFilters,
        tasksRuntimeP95: std.strReplace(queries.tasksRuntimeP50, '0.50', '0.95'),
        tasksRuntimeP99: std.strReplace(queries.tasksRuntimeP50, '0.50', '0.99'),

        // Pie chart queries — instant or 6h fixed window
        queueLengthByQueue: |||
          topk(10,
            sum(
              celery_queue_length{
                %(defaultQueue)s
              }
            ) by (queue_name)
          )
        ||| % defaultFilters,

        taskRateByName6h: |||
          topk(10,
            sum(
              rate(
                celery_task_received_total{
                  %(defaultQueue)s
                }[6h]
              )
            ) by (name)
          )
        ||| % defaultFilters,

        taskSucceeded6hPie: |||
          sum(
            increase(
              celery_task_succeeded_total{
                %(defaultQueue)s
              }[6h]
            )
          )
        ||| % defaultFilters,
        taskFailed6hPie: |||
          sum(
            increase(
              celery_task_failed_total{
                %(defaultQueue)s
              }[6h]
            )
          )
        ||| % defaultFilters,

        taskSent6h: |||
          sum(
            increase(
              celery_task_sent_total{
                %(defaultQueue)s
              }[6h]
            )
          )
        ||| % defaultFilters,
        taskReceived6h: |||
          sum(
            increase(
              celery_task_received_total{
                %(defaultQueue)s
              }[6h]
            )
          )
        ||| % defaultFilters,
        taskRetried6h: |||
          sum(
            increase(
              celery_task_retried_total{
                %(defaultQueue)s
              }[6h]
            )
          )
        ||| % defaultFilters,
        taskRevoked6h: |||
          sum(
            increase(
              celery_task_revoked_total{
                %(defaultQueue)s
              }[6h]
            )
          )
        ||| % defaultFilters,
        taskRejected6h: |||
          sum(
            increase(
              celery_task_rejected_total{
                %(defaultQueue)s
              }[6h]
            )
          )
        ||| % defaultFilters,
      };

      local panels = {

        celeryWorkersStat:
          mixinUtils.dashboards.statPanel(
            'Workers',
            'short',
            queries.celeryWorkers,
            description='Number of active Celery Workers',
          ),

        celeryWorkersActiveStat:
          mixinUtils.dashboards.statPanel(
            'Workers Active Tasks',
            'short',
            queries.celeryWorkersActive,
            description='Number of active tasks across all workers',
          ),

        queueCountStat:
          mixinUtils.dashboards.statPanel(
            'Queues',
            'short',
            queries.queueCount,
            description='Number of distinct queues with reported queue length',
          ),

        tasksReceivedByWorkers24hStat:
          mixinUtils.dashboards.statPanel(
            'Tasks received by workers [1w]',
            'short',
            queries.tasksReceived1w,
            description='Number of tasks received by workers in the last week',
          ),

        taskSuccessRate1wStat:
          mixinUtils.dashboards.statPanel(
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
          mixinUtils.dashboards.statPanel(
            'Average Runtime for Tasks [1w]',
            's',
            queries.taskRuntime1w,
            description='Average runtime for tasks in the last week',
          ),

        // Pie charts
        queueLengthByQueuePieChart:
          mixinUtils.dashboards.pieChartPanel(
            'Queue Length by Queue',
            'short',
            queries.queueLengthByQueue,
            '{{ queue_name }}',
            description='Current queue depth across all queues (top 10 by length). Shows which queues have the most pending tasks. A growing queue indicates workers cannot keep up with the arrival rate.',
          ),

        taskRateByNamePieChart:
          mixinUtils.dashboards.pieChartPanel(
            'Task Rate by Name [6h]',
            'reqps',
            queries.taskRateByName6h,
            '{{ name }}',
            description='Top 10 task types by throughput over the past 6 hours. Identifies which tasks run most frequently. High-volume tasks are candidates for optimization and dedicated worker queues.',
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
            description='Overall task health split between succeeded and failed tasks in the past 6 hours. Any visible failure slice warrants investigation. Compare with the Top Failed Tasks table to identify which tasks are contributing to failures.',
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
            description='Distribution of all task lifecycle states over the past 6 hours. A healthy system shows predominantly Succeeded tasks. Significant Retried or Rejected slices indicate reliability issues. Revoked tasks suggest manual cancellations or timeouts.',
          ),

        tasksFailed1wTable:
          mixinUtils.dashboards.tablePanel(
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
          ) +
          tbStandardOptions.withLinks([
            tbPanelOptions.link.withTitle('Go To Task') +
            tbPanelOptions.link.withType('dashboard') +
            tbPanelOptions.link.withUrl(
              '/d/%s/celery-tasks-by-task?var-namespace=${namespace}&var-job=${job}&var-task=${__data.fields.Task}' % $._config.dashboardIds['celery-tasks-by-task']
            ) +
            tbPanelOptions.link.withTargetBlank(true),
          ]),

        taskExceptions1wTable:
          mixinUtils.dashboards.tablePanel(
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
          mixinUtils.dashboards.tablePanel(
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
          ) +
          tbStandardOptions.withLinks([
            tbPanelOptions.link.withTitle('Go To Task') +
            tbPanelOptions.link.withType('dashboard') +
            tbPanelOptions.link.withUrl(
              '/d/%s/celery-tasks-by-task?var-namespace=${namespace}&var-job=${job}&var-task=${__data.fields.Task}' % $._config.dashboardIds['celery-tasks-by-task']
            ) +
            tbPanelOptions.link.withTargetBlank(true),
          ]),

        celeryQueueLengthTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'Queue Length',
            'short',
            queries.celeryQueueLength,
            '{{ job }}/{{ queue_name }}',
            description='Length of Celery queues',
            stack='normal'
          ),

        tasksStatsTable:
          mixinUtils.dashboards.tablePanel(
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
          mixinUtils.dashboards.timeSeriesPanel(
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
            panels.queueCountStat,
            panels.tasksReceivedByWorkers24hStat,
            panels.taskSuccessRate1wStat,
            panels.taskRuntime1wStat,
          ],
          panelWidth=4,
          panelHeight=3,
          startY=1
        ) +
        grid.wrapPanels(
          [
            panels.queueLengthByQueuePieChart,
            panels.taskRateByNamePieChart,
            panels.taskSuccessVsFailurePieChart,
            panels.taskStatesPieChart,
          ],
          panelWidth=6,
          panelHeight=5,
          startY=4
        ) +
        [
          row.new(
            'Queues'
          ) +
          row.gridPos.withX(0) +
          row.gridPos.withY(9) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
          panels.celeryQueueLengthTimeSeries +
          timeSeriesPanel.gridPos.withX(0) +
          timeSeriesPanel.gridPos.withY(10) +
          timeSeriesPanel.gridPos.withW(24) +
          timeSeriesPanel.gridPos.withH(6),
        ] +
        [
          row.new(
            'Tasks'
          ) +
          row.gridPos.withX(0) +
          row.gridPos.withY(16) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
          panels.tasksStatsTable +
          tablePanel.gridPos.withX(0) +
          tablePanel.gridPos.withY(17) +
          tablePanel.gridPos.withW(24) +
          tablePanel.gridPos.withH(5),
          panels.tasksCompletedTimeSeries +
          timeSeriesPanel.gridPos.withX(0) +
          timeSeriesPanel.gridPos.withY(22) +
          timeSeriesPanel.gridPos.withW(12) +
          timeSeriesPanel.gridPos.withH(8),
          panels.tasksRuntimeTimeSeries +
          timeSeriesPanel.gridPos.withX(12) +
          timeSeriesPanel.gridPos.withY(22) +
          timeSeriesPanel.gridPos.withW(12) +
          timeSeriesPanel.gridPos.withH(8),
        ] +
        [
          row.new(
            'Weekly Breakdown'
          ) +
          row.gridPos.withX(0) +
          row.gridPos.withY(30) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        grid.wrapPanels(
          [
            panels.tasksFailed1wTable,
            panels.taskExceptions1wTable,
            panels.tasksRuntime1wTable,
          ],
          panelWidth=8,
          panelHeight=8,
          startY=31
        );

      mixinUtils.dashboards.bypassDashboardValidation +
      dashboard.new(
        'Celery / Tasks / Overview',
      ) +
      dashboard.withDescription('A dashboard that gives an overview of Celery. %s' % mixinUtils.dashboards.dashboardDescriptionLink('celery-exporter', 'https://github.com/danihodovic/celery-exporter')) +
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
