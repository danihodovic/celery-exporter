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

        // Summary
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
                %(queue)s
              }
            )
          )
        ||| % defaultFilters,

        queueLengthTotal: |||
          sum(
            celery_queue_length{
              %(queue)s
            }
          )
        ||| % defaultFilters,

        taskRate1h: |||
          sum(
            rate(
              celery_task_received_total{
                %(queue)s
              }[1h]
            )
          )
        ||| % defaultFilters,

        taskSuccessRate1h: |||
          sum(
            rate(
              celery_task_succeeded_total{
                %(queue)s
              }[1h]
            )
          )
          /
          (
            sum(
              rate(
                celery_task_succeeded_total{
                  %(queue)s
                }[1h]
              )
            )
            +
            sum(
              rate(
                celery_task_failed_total{
                  %(queue)s
                }[1h]
              )
            )
          )
        ||| % defaultFilters,

        // Pie charts
        queueLengthByQueue: |||
          topk(10,
            sum(
              celery_queue_length{
                %(defaultQueue)s
              }
            ) by (queue_name)
          )
        ||| % defaultFilters,

        taskRateByName1h: |||
          topk(10,
            sum(
              rate(
                celery_task_received_total{
                  %(queue)s
                }[1h]
              )
            ) by (name)
          )
        ||| % defaultFilters,

        taskRateByQueue1h: |||
          topk(10,
            sum(
              rate(
                celery_task_received_total{
                  %(defaultQueue)s
                }[1h]
              )
            ) by (queue_name)
          )
        ||| % defaultFilters,

        taskFailed1h: |||
          sum(
            increase(
              celery_task_failed_total{
                %(queue)s
              }[1h]
            )
          )
        ||| % defaultFilters,
        taskSucceeded1h: std.strReplace(queries.taskFailed1h, 'failed', 'succeeded'),
        taskRetried1h: std.strReplace(queries.taskFailed1h, 'failed', 'retried'),
        taskRevoked1h: std.strReplace(queries.taskFailed1h, 'failed', 'revoked'),
        taskRejected1h: std.strReplace(queries.taskFailed1h, 'failed', 'rejected'),

        // Queues
        queueLength: |||
          sum(
            celery_queue_length{
              %(queue)s
            }
          ) by (queue_name)
        ||| % defaultFilters,

        taskRateByQueue: |||
          sum(
            rate(
              celery_task_received_total{
                %(queue)s
              }[$__rate_interval]
            )
          ) by (queue_name)
        ||| % defaultFilters,

        queueWaitTimeP50: |||
          histogram_quantile(0.50,
            sum(
              rate(
                celery_task_queue_wait_time_bucket{
                  %(queue)s
                }[$__rate_interval]
              )
            ) by (le)
          )
        ||| % defaultFilters,
        queueWaitTimeP95: std.strReplace(queries.queueWaitTimeP50, '0.50', '0.95'),
        queueWaitTimeP99: std.strReplace(queries.queueWaitTimeP50, '0.50', '0.99'),

        // Tasks


        taskFailedRate: |||
          sum(
            rate(
              celery_task_failed_total{
                %(queue)s
              }[$__rate_interval]
            )
          )
        ||| % defaultFilters,
        taskSucceededRate: std.strReplace(queries.taskFailedRate, 'failed', 'succeeded'),
        taskSentRate: std.strReplace(queries.taskFailedRate, 'failed', 'sent'),
        taskReceivedRate: std.strReplace(queries.taskFailedRate, 'failed', 'received'),
        taskRetriedRate: std.strReplace(queries.taskFailedRate, 'failed', 'retried'),
        taskRevokedRate: std.strReplace(queries.taskFailedRate, 'failed', 'revoked'),
        taskRejectedRate: std.strReplace(queries.taskFailedRate, 'failed', 'rejected'),

        taskSuccessRate: |||
          %s
          /
          (
            %s
            +
            %s
          )
        ||| % [queries.taskSucceededRate, queries.taskSucceededRate, queries.taskFailedRate],

        tasksRuntimeP50: |||
          histogram_quantile(0.50,
            sum(
              rate(
                celery_task_runtime_bucket{
                  %(queue)s
                }[$__rate_interval]
              )
            ) by (le)
          )
        ||| % defaultFilters,
        tasksRuntimeP95: std.strReplace(queries.tasksRuntimeP50, '0.50', '0.95'),
        tasksRuntimeP99: std.strReplace(queries.tasksRuntimeP50, '0.50', '0.99'),

        // Tasks table, limited to the 40 busiest tasks in the last 24 hours
        taskRateByName24hTop40: |||
          topk(40,
            sum(
              rate(
                celery_task_received_total{
                  %(queue)s
                }[24h]
              )
            ) by (job, name)
          )
        ||| % defaultFilters,
        local top40 = {
          top40: |||
            and on (job, name) (
              %s
            )
          ||| % queries.taskRateByName24hTop40,
        },

        taskSucceededByName24h: |||
          round(
            sum(
              increase(
                celery_task_succeeded_total{
                  %(queue)s
                }[24h]
              )
            ) by (job, name)
          )
          %(top40)s
        ||| % (defaultFilters + top40),
        taskFailedByName24h: std.strReplace(queries.taskSucceededByName24h, 'succeeded', 'failed'),
        taskRetriedByName24h: std.strReplace(queries.taskSucceededByName24h, 'succeeded', 'retried'),

        taskSuccessRateByName24h: |||
          sum(
            rate(
              celery_task_succeeded_total{
                %(queue)s
              }[24h]
            )
          ) by (job, name)
          /
          (
            sum(
              rate(
                celery_task_succeeded_total{
                  %(queue)s
                }[24h]
              )
            ) by (job, name)
            +
            sum(
              rate(
                celery_task_failed_total{
                  %(queue)s
                }[24h]
              )
            ) by (job, name)
          )
          %(top40)s
        ||| % (defaultFilters + top40),

        taskRuntimeP50ByName24h: |||
          histogram_quantile(0.50,
            sum(
              rate(
                celery_task_runtime_bucket{
                  %(queue)s
                }[24h]
              )
            ) by (le, job, name)
          )
          %(top40)s
        ||| % (defaultFilters + top40),
        taskRuntimeP95ByName24h: std.strReplace(queries.taskRuntimeP50ByName24h, '0.50', '0.95'),

        taskQueueWaitTimeP95ByName24h: |||
          histogram_quantile(0.95,
            sum(
              rate(
                celery_task_queue_wait_time_bucket{
                  %(queue)s
                }[24h]
              )
            ) by (le, job, name)
          )
          %(top40)s
        ||| % (defaultFilters + top40),

        taskExceptions24h: |||
          round(
            sum(
              increase(
                celery_task_failed_total{
                  %(queue)s
                }[24h]
              )
            ) by (job, name, exception)
          ) > 0
        ||| % defaultFilters,
      };

      local panels = {

        // Summary
        celeryWorkersStat:
          mixinUtils.dashboards.statPanel(
            'Workers',
            'short',
            queries.celeryWorkers,
            description='Number of Celery workers currently reporting as up. A sudden drop means workers crashed or were scaled down.',
          ),

        celeryWorkersActiveStat:
          mixinUtils.dashboards.statPanel(
            'Active Tasks',
            'short',
            queries.celeryWorkersActive,
            description='Number of tasks currently executing across all workers.',
          ),

        queueCountStat:
          mixinUtils.dashboards.statPanel(
            'Queues',
            'short',
            queries.queueCount,
            description='Number of distinct queues with reported queue length.',
          ),

        queueLengthTotalStat:
          mixinUtils.dashboards.statPanel(
            'Queued Tasks',
            'short',
            queries.queueLengthTotal,
            description='Total number of tasks waiting in all queues. A growing value means workers cannot keep up with the arrival rate.',
          ),

        taskRate1hStat:
          mixinUtils.dashboards.statPanel(
            'Task Rate [1h]',
            'ops',
            queries.taskRate1h,
            description='Average rate of tasks received by workers over the last hour.',
          ),

        taskSuccessRate1hStat:
          mixinUtils.dashboards.statPanel(
            'Task Success Rate [1h]',
            'percentunit',
            queries.taskSuccessRate1h,
            description='Share of finished tasks that succeeded over the last hour.',
            steps=[
              stStandardOptions.threshold.step.withValue(0) +
              stStandardOptions.threshold.step.withColor('red'),
              stStandardOptions.threshold.step.withValue(0.95) +
              stStandardOptions.threshold.step.withColor('yellow'),
              stStandardOptions.threshold.step.withValue(0.99) +
              stStandardOptions.threshold.step.withColor('green'),
            ]
          ),

        queueLengthByQueuePieChart:
          mixinUtils.dashboards.pieChartPanel(
            'Queue Length by Queue',
            'short',
            queries.queueLengthByQueue,
            '{{ queue_name }}',
            description='Current queue depth across queues (top 10 by length). Shows which queues have the most pending tasks.',
          ),

        taskRateByNamePieChart:
          mixinUtils.dashboards.pieChartPanel(
            'Task Rate by Name [1h]',
            'ops',
            queries.taskRateByName1h,
            '{{ name }}',
            description='Top 10 tasks by throughput over the last hour. High-volume tasks are candidates for optimization and dedicated worker queues.',
          ),

        taskRateByQueuePieChart:
          mixinUtils.dashboards.pieChartPanel(
            'Task Rate by Queue [1h]',
            'ops',
            queries.taskRateByQueue1h,
            '{{ queue_name }}',
            description='Top 10 queues by task throughput over the last hour.',
          ),

        taskStatesPieChart:
          mixinUtils.dashboards.pieChartPanel(
            'Task Outcomes [1h]',
            'short',
            [
              {
                expr: queries.taskSucceeded1h,
                legend: 'Succeeded',
              },
              {
                expr: queries.taskFailed1h,
                legend: 'Failed',
              },
              {
                expr: queries.taskRetried1h,
                legend: 'Retried',
              },
              {
                expr: queries.taskRevoked1h,
                legend: 'Revoked',
              },
              {
                expr: queries.taskRejected1h,
                legend: 'Rejected',
              },
            ],
            description='Distribution of task outcomes over the last hour. A healthy system is predominantly Succeeded. Significant Retried or Rejected slices indicate reliability issues.',
          ),

        // Queues
        queueLengthTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'Queue Length',
            'short',
            queries.queueLength,
            '{{ queue_name }}',
            description='Number of tasks waiting in each queue.',
            stack='normal'
          ),

        taskRateByQueueTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'Task Rate by Queue',
            'ops',
            queries.taskRateByQueue,
            '{{ queue_name }}',
            description='Rate of tasks received by workers per queue.',
            stack='normal'
          ),

        queueWaitTimeTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'Queue Wait Time',
            's',
            [
              {
                expr: queries.queueWaitTimeP50,
                legend: 'P50',
              },
              {
                expr: queries.queueWaitTimeP95,
                legend: 'P95',
              },
              {
                expr: queries.queueWaitTimeP99,
                legend: 'P99',
              },
            ],
            description='Time tasks spend in the queue between being sent and starting on a worker. Requires task_send_sent_event to be enabled on the client. Rising values mean workers are saturated.',
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

        // Tasks


        taskStatesTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'Task States',
            'ops',
            [
              {
                expr: queries.taskSucceededRate,
                legend: 'Succeeded',
              },
              {
                expr: queries.taskFailedRate,
                legend: 'Failed',
              },
              {
                expr: queries.taskSentRate,
                legend: 'Sent',
              },
              {
                expr: queries.taskReceivedRate,
                legend: 'Received',
              },
              {
                expr: queries.taskRetriedRate,
                legend: 'Retried',
              },
              {
                expr: queries.taskRevokedRate,
                legend: 'Revoked',
              },
              {
                expr: queries.taskRejectedRate,
                legend: 'Rejected',
              },
            ],
            description='Rate of task lifecycle events over time.',
          ),

        taskSuccessRateTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'Task Success Rate',
            'percentunit',
            queries.taskSuccessRate,
            'Success Rate',
            description='Share of finished tasks that succeeded.',
            min=0,
            max=1,
          ),

        tasksRuntimeTimeSeries:
          mixinUtils.dashboards.timeSeriesPanel(
            'Task Runtime',
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
            description='Task runtime percentiles across all tasks.',
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

        tasksTable:
          mixinUtils.dashboards.tablePanel(
            'Tasks Overview [24h]',
            'short',
            [
              {
                expr: queries.taskRateByName24hTop40,
              },
              {
                expr: queries.taskSucceededByName24h,
              },
              {
                expr: queries.taskFailedByName24h,
              },
              {
                expr: queries.taskRetriedByName24h,
              },
              {
                expr: queries.taskSuccessRateByName24h,
              },
              {
                expr: queries.taskRuntimeP50ByName24h,
              },
              {
                expr: queries.taskRuntimeP95ByName24h,
              },
              {
                expr: queries.taskQueueWaitTimeP95ByName24h,
              },
            ],
            description='Per-task statistics over the last 24 hours for the 40 busiest tasks. Click a task to open it in the Celery / Tasks / By Task dashboard.',
            sortBy={
              name: 'Rate',
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
                    name: 'Task',
                    job: 'Job',
                    'Value #A': 'Rate',
                    'Value #B': 'Succeeded',
                    'Value #C': 'Failed',
                    'Value #D': 'Retried',
                    'Value #E': 'Success Rate',
                    'Value #F': 'P50 Runtime',
                    'Value #G': 'P95 Runtime',
                    'Value #H': 'P95 Queue Wait',
                  },
                  indexByName: {
                    name: 0,
                    job: 1,
                    'Value #A': 2,
                    'Value #B': 3,
                    'Value #C': 4,
                    'Value #D': 5,
                    'Value #E': 6,
                    'Value #F': 7,
                    'Value #G': 8,
                    'Value #H': 9,
                  },
                  excludeByName: {
                    Time: true,
                    job: true,
                  },
                }
              ),
            ],
            overrides=[
              tbOverride.byName.new('Rate') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('ops')
              ),
              tbOverride.byName.new('Success Rate') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('percentunit')
              ),
              tbOverride.byName.new('P50 Runtime') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('s')
              ),
              tbOverride.byName.new('P95 Runtime') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('s')
              ),
              tbOverride.byName.new('P95 Queue Wait') +
              tbOverride.byName.withPropertiesFromOptions(
                tbStandardOptions.withUnit('s')
              ),
            ],
          ) +
          tbStandardOptions.withNoValue(0) +
          tbStandardOptions.withLinks([
            tbPanelOptions.link.withTitle('Go To Task') +
            tbPanelOptions.link.withType('dashboard') +
            tbPanelOptions.link.withUrl(
              '/d/%s/celery-tasks-by-task?var-namespace=${namespace}&var-job=${job}&var-task=${__data.fields.Task}' % $._config.dashboardIds['celery-tasks-by-task']
            ) +
            tbPanelOptions.link.withTargetBlank(true),
          ]),

        taskExceptionsTable:
          mixinUtils.dashboards.tablePanel(
            'Task Exceptions [24h]',
            'short',
            queries.taskExceptions24h,
            description='Failed task runs over the last 24 hours, grouped by task and exception.',
            sortBy={
              name: 'Failures',
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
                    exception: 'Exception',
                    Value: 'Failures',
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
            panels.celeryWorkersStat,
            panels.celeryWorkersActiveStat,
            panels.queueCountStat,
            panels.queueLengthTotalStat,
            panels.taskRate1hStat,
            panels.taskSuccessRate1hStat,
          ],
          panelWidth=4,
          panelHeight=3,
          startY=1
        ) +
        grid.wrapPanels(
          [
            panels.queueLengthByQueuePieChart,
            panels.taskRateByQueuePieChart,
            panels.taskRateByNamePieChart,
            panels.taskStatesPieChart,
          ],
          panelWidth=6,
          panelHeight=6,
          startY=4
        ) +
        [
          row.new('Tasks') +
          row.gridPos.withX(0) +
          row.gridPos.withY(10) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        grid.wrapPanels(
          [
            panels.taskStatesTimeSeries,
            panels.taskSuccessRateTimeSeries,
          ],
          panelWidth=12,
          panelHeight=8,
          startY=11
        ) +
        grid.wrapPanels(
          [
            panels.tasksRuntimeTimeSeries,
          ],
          panelWidth=24,
          panelHeight=8,
          startY=19
        ) +
        grid.wrapPanels(
          [
            panels.tasksTable,
          ],
          panelWidth=24,
          panelHeight=12,
          startY=27
        ) +
        grid.wrapPanels(
          [
            panels.taskExceptionsTable,
          ],
          panelWidth=24,
          panelHeight=8,
          startY=39
        ) +
        [
          row.new('Queues') +
          row.gridPos.withX(0) +
          row.gridPos.withY(47) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        grid.wrapPanels(
          [
            panels.queueLengthTimeSeries,
            panels.taskRateByQueueTimeSeries,
          ],
          panelWidth=12,
          panelHeight=8,
          startY=48
        ) +
        grid.wrapPanels(
          [
            panels.queueWaitTimeTimeSeries,
          ],
          panelWidth=24,
          panelHeight=8,
          startY=56
        );

      mixinUtils.dashboards.bypassDashboardValidation +
      dashboard.new(
        'Celery / Tasks / Overview',
      ) +
      dashboard.withDescription('An overview of Celery workers, queues and task runs. Shows task throughput, success rate, runtime and queue wait time, with a per-task table that links to the Celery / Tasks / By Task dashboard. %s' % mixinUtils.dashboards.dashboardDescriptionLink('celery-exporter', 'https://github.com/danihodovic/celery-exporter')) +
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
