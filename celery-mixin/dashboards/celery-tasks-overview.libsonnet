local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';

local dashboard = g.dashboard;
local row = g.panel.row;
local grid = g.util.grid;

local variable = dashboard.variable;
local datasource = variable.datasource;
local query = variable.query;
local prometheus = g.query.prometheus;

local statPanel = g.panel.stat;
local timeSeriesPanel = g.panel.timeSeries;
local tablePanel = g.panel.table;

// Stat
local stOptions = statPanel.options;
local stStandardOptions = statPanel.standardOptions;
local stQueryOptions = statPanel.queryOptions;

// Timeseries
local tsOptions = timeSeriesPanel.options;
local tsStandardOptions = timeSeriesPanel.standardOptions;
local tsQueryOptions = timeSeriesPanel.queryOptions;
local tsFieldConfig = timeSeriesPanel.fieldConfig;
local tsCustom = tsFieldConfig.defaults.custom;
local tsLegend = tsOptions.legend;
local tsOverride = tsStandardOptions.override;

// Table
local tbOptions = tablePanel.options;
local tbStandardOptions = tablePanel.standardOptions;
local tbQueryOptions = tablePanel.queryOptions;
local tbPanelOptions = tablePanel.panelOptions;
local tbOverride = tbStandardOptions.override;

{
  grafanaDashboards+:: {

    local datasourceVariable =
      datasource.new(
        'datasource',
        'prometheus',
      ) +
      datasource.generalOptions.withLabel('Data source'),

    local namespaceVariable =
      query.new(
        'namespace',
        'label_values(celery_worker_up{}, namespace)'
      ) +
      query.withDatasourceFromVariable(datasourceVariable) +
      query.withSort(1) +
      query.generalOptions.withLabel('Namespace') +
      query.selectionOptions.withMulti(false) +
      query.selectionOptions.withIncludeAll(false) +
      query.refresh.onLoad() +
      query.refresh.onTime(),


    local jobVariable =
      query.new(
        'job',
        'label_values(celery_worker_up{namespace="$namespace"}, job)'
      ) +
      query.withDatasourceFromVariable(datasourceVariable) +
      query.withSort(1) +
      query.generalOptions.withLabel('Job') +
      query.selectionOptions.withMulti(false) +
      query.selectionOptions.withIncludeAll(false) +
      query.refresh.onLoad() +
      query.refresh.onTime(),

    local queueNameVariable =
      query.new(
        'queue_name',
        'label_values(celery_task_received_total{namespace="$namespace", job="$job", name!~"%(celeryIgnoredQueues)s"}, queue_name)' % $._config
      ) +
      query.withDatasourceFromVariable(datasourceVariable) +
      query.withSort(1) +
      query.generalOptions.withLabel('Queue Name') +
      query.selectionOptions.withMulti(false) +
      query.selectionOptions.withIncludeAll(false) +
      query.refresh.onLoad() +
      query.refresh.onTime(),

    local variables = [
      datasourceVariable,
      namespaceVariable,
      jobVariable,
      queueNameVariable,
    ],

    local celeryWorkersQuery = |||
      count(
        celery_worker_up{
          job="$job",
        } == 1
      )
    |||,
    local celeryWorkersStatPanel =
      statPanel.new(
        'Workers',
      ) +
      stQueryOptions.withTargets(
        prometheus.new(
          '$datasource',
          celeryWorkersQuery,
        )
      ) +
      stStandardOptions.withUnit('short') +
      stOptions.reduceOptions.withCalcs(['lastNotNull']) +
      stStandardOptions.thresholds.withSteps([
        stStandardOptions.threshold.step.withValue(0) +
        stStandardOptions.threshold.step.withColor('red'),
        stStandardOptions.threshold.step.withValue(0.1) +
        stStandardOptions.threshold.step.withColor('green'),
      ]),

    local celeryWorkersActiveQuery = |||
      sum(
        celery_worker_tasks_active{
          job="$job",
        }
      )
    |||,
    local celeryWorkersActiveStatPanel =
      statPanel.new(
        'Tasks Active',
      ) +
      stQueryOptions.withTargets(
        prometheus.new(
          '$datasource',
          celeryWorkersActiveQuery,
        )
      ) +
      stStandardOptions.withUnit('short') +
      stOptions.reduceOptions.withCalcs(['lastNotNull']) +
      stStandardOptions.thresholds.withSteps([
        stStandardOptions.threshold.step.withValue(0) +
        stStandardOptions.threshold.step.withColor('red'),
        stStandardOptions.threshold.step.withValue(0.1) +
        stStandardOptions.threshold.step.withColor('green'),
      ]),

    local taskFailed1wQuery = |||
      sum(
        round(
          increase(
            celery_task_failed_total{
              job="$job",
              queue_name=~"$queue_name"
            }[1w]
          )
        )
      )
    |||,
    local taskSucceeded1wQuery = std.strReplace(taskFailed1wQuery, 'failed', 'succeeded'),

    local tasksReceived1wQuery = std.strReplace(taskFailed1wQuery, 'failed', 'received'),
    local tasksReceivedByWorkers24hStatPanel =
      statPanel.new(
        'Tasks received by workers [1w]',
      ) +
      stQueryOptions.withTargets(
        prometheus.new(
          '$datasource',
          tasksReceived1wQuery,
        )
      ) +
      stStandardOptions.withUnit('short') +
      stOptions.reduceOptions.withCalcs(['lastNotNull']) +
      stStandardOptions.thresholds.withSteps([
        stStandardOptions.threshold.step.withValue(0) +
        stStandardOptions.threshold.step.withColor('red'),
        stStandardOptions.threshold.step.withValue(0.1) +
        stStandardOptions.threshold.step.withColor('green'),
      ]),

    local taskSuccessRate1wQuery = |||
      %s/(%s+%s)
    ||| % [taskSucceeded1wQuery, taskSucceeded1wQuery, taskFailed1wQuery],
    local taskSuccessRate1wStatPanel =
      statPanel.new(
        'Tasks Success Rate [1w]',
      ) +
      stQueryOptions.withTargets(
        prometheus.new(
          '$datasource',
          taskSuccessRate1wQuery,
        )
      ) +
      stStandardOptions.withUnit('percentunit') +
      stOptions.reduceOptions.withCalcs(['lastNotNull']) +
      stStandardOptions.thresholds.withSteps([
        stStandardOptions.threshold.step.withValue(0) +
        stStandardOptions.threshold.step.withColor('red'),
        stStandardOptions.threshold.step.withValue(0.95) +
        stStandardOptions.threshold.step.withColor('yellow'),
        stStandardOptions.threshold.step.withValue(0.99) +
        stStandardOptions.threshold.step.withColor('green'),
      ]),

    local taskRuntime1wQuery = |||
      sum(
        rate(
          celery_task_runtime_sum{
            job="$job",
            queue_name=~"$queue_name"
          }[1w]
        )
      )
      /
      sum(
        rate(
          celery_task_runtime_count{
            job="$job",
            queue_name=~"$queue_name"
          }[1w]
        )
      ) > 0
    |||,
    local taskRuntime1wStatPanel =
      statPanel.new(
        'Average Runtime for Tasks [1w]',
      ) +
      stQueryOptions.withTargets(
        prometheus.new(
          '$datasource',
          taskRuntime1wQuery,
        )
      ) +
      stStandardOptions.withUnit('s') +
      stOptions.reduceOptions.withCalcs(['lastNotNull']) +
      stStandardOptions.thresholds.withSteps([
        stStandardOptions.threshold.step.withValue(0) +
        stStandardOptions.threshold.step.withColor('red'),
        stStandardOptions.threshold.step.withValue(0.1) +
        stStandardOptions.threshold.step.withColor('green'),
      ]),

    local tasksFailed1wQuery = |||
      round(
        sum (
          increase(
            celery_task_failed_total{
              job="$job",
              queue_name=~"$queue_name"
            }[1w]
          ) > 0
        )  by (job, name)
      )
    |||,
    local tasksFailed1wTable =
      tablePanel.new(
        'Top Failed Tasks [1w]',
      ) +
      tbStandardOptions.withUnit('short') +
      tbOptions.withSortBy(
        tbOptions.sortBy.withDisplayName('Value') +
        tbOptions.sortBy.withDesc(true)
      ) +
      tbOptions.footer.withEnablePagination(true) +
      tbQueryOptions.withTargets(
        prometheus.new(
          '$datasource',
          tasksFailed1wQuery,
        ) +
        prometheus.withFormat('table') +
        prometheus.withInstant(true)
      ) +
      tbQueryOptions.withTransformations([
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
      ]) +
      tbStandardOptions.withOverrides([
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
      ]),

    local topTaskExceptions1wQuery = |||
      round(
        sum (
          increase(
            celery_task_failed_total{
              job="$job",
              queue_name=~"$queue_name"
            }[1w]
          )
        ) by (job, exception) > 0
      )
    |||,

    local taskExceptions1wTable =
      tablePanel.new(
        'Top Task Exceptions [1w]',
      ) +
      tbStandardOptions.withUnit('short') +
      tbOptions.withSortBy(
        tbOptions.sortBy.withDisplayName('Value') +
        tbOptions.sortBy.withDesc(true)
      ) +
      tbOptions.footer.withEnablePagination(true) +
      tbQueryOptions.withTargets(
        prometheus.new(
          '$datasource',
          topTaskExceptions1wQuery,
        ) +
        prometheus.withFormat('table') +
        prometheus.withInstant(true)
      ) +
      tbQueryOptions.withTransformations([
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
      ]),

    local topTaskRuntime1wQuery = |||
      sum (
        rate(
          celery_task_runtime_sum{
            job="$job",
            queue_name=~"$queue_name"
          }[1w]
        )
      ) by(name)
      /
      sum (
        rate(
          celery_task_runtime_count{
            job="$job",
            queue_name=~"$queue_name"
          }[1w]
        )
      ) by (name) > 0
    |||,
    local tasksRuntime1wTable =
      tablePanel.new(
        'Top Average Task Runtime [1w]',
      ) +
      tbStandardOptions.withUnit('s') +
      tbOptions.withSortBy(
        tbOptions.sortBy.withDisplayName('Runtime') +
        tbOptions.sortBy.withDesc(true)
      ) +
      tbOptions.footer.withEnablePagination(true) +
      tbQueryOptions.withTargets(
        prometheus.new(
          '$datasource',
          topTaskRuntime1wQuery,
        ) +
        prometheus.withFormat('table') +
        prometheus.withInstant(true)
      ) +
      tbQueryOptions.withTransformations([
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
      ]) +
      tbStandardOptions.withOverrides([
        tbOverride.byName.new('Task') +
        tbOverride.byName.withPropertiesFromOptions(
          tbStandardOptions.withLinks(
            tbPanelOptions.link.withTitle('Go To Task') +
            tbPanelOptions.link.withType('dashboard') +
            tbPanelOptions.link.withUrl(
              '/d/%s/celery-tasks-by-task?var-task=${__data.fields.Task}' % $._config.celeryTasksByTaskUid
            ) +
            tbPanelOptions.link.withTargetBlank(true)
          )
        ),
      ]),

    local celeryQueueLengthQuery = |||
      sum (
        celery_queue_length{
          job="$job",
          queue_name=~"$queue_name"
        }
      ) by (job, queue_name)
    |||,


    local celeryQueueLengthTimeSeriesPanel =
      timeSeriesPanel.new(
        'Queue Length',
      ) +
      tsQueryOptions.withTargets(
        [
          prometheus.new(
            '$datasource',
            celeryQueueLengthQuery,
          ) +
          prometheus.withLegendFormat(
            '{{ job }}/{{ queue_name }}'
          ),
        ]
      ) +
      tsStandardOptions.withUnit('short') +
      tsOptions.tooltip.withMode('multi') +
      tsOptions.tooltip.withSort('desc') +
      tsLegend.withShowLegend(true) +
      tsLegend.withDisplayMode('table') +
      tsLegend.withPlacement('right') +
      tsLegend.withCalcs(['mean', 'max']) +
      tsLegend.withSortBy('Mean') +
      tsLegend.withSortDesc(true) +
      tsCustom.withSpanNulls(false),

    local taskFailedQuery = |||
      sum (
        round(
          increase(
            celery_task_failed_total{
              job="$job",
              queue_name=~"$queue_name"
            }[$__range]
          )
        )
      ) by (job) > 0
    |||,
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
      tablePanel.new(
        'Task Stats',
      ) +
      tbStandardOptions.withUnit('short') +
      tbStandardOptions.withNoValue(0) +
      tbOptions.withSortBy(
        tbOptions.sortBy.withDisplayName('Succeeded') +
        tbOptions.sortBy.withDesc(true)
      ) +
      tbQueryOptions.withTargets(
        [
          prometheus.new(
            '$datasource',
            taskSuccessRateQuery,
          ) +
          prometheus.withFormat('table') +
          prometheus.withInstant(true),
          prometheus.new(
            '$datasource',
            taskSucceededQuery,
          ) +
          prometheus.withFormat('table') +
          prometheus.withInstant(true),
          prometheus.new(
            '$datasource',
            taskFailedQuery,
          ) +
          prometheus.withFormat('table') +
          prometheus.withInstant(true),
          prometheus.new(
            '$datasource',
            taskSentQuery,
          ) +
          prometheus.withFormat('table') +
          prometheus.withInstant(true),
          prometheus.new(
            '$datasource',
            taskReceivedQuery,
          ) +
          prometheus.withFormat('table') +
          prometheus.withInstant(true),
          prometheus.new(
            '$datasource',
            taskRejectedQuery,
          ) +
          prometheus.withFormat('table') +
          prometheus.withInstant(true),
          prometheus.new(
            '$datasource',
            taskRetriedQuery,
          ) +
          prometheus.withFormat('table') +
          prometheus.withInstant(true),
          prometheus.new(
            '$datasource',
            taskRevokedQuery,
          ) +
          prometheus.withFormat('table') +
          prometheus.withInstant(true),
        ]
      ) +
      tbQueryOptions.withTransformations([
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
      ]) +
      tbStandardOptions.withOverrides([
        tbOverride.byName.new('Success Rate') +
        tbOverride.byName.withPropertiesFromOptions(
          tbStandardOptions.withUnit('percentunit')
        ),
      ]),

    local taskFailedIntervalQuery = |||
      sum (
        round(
          increase(
            celery_task_failed_total{
              job="$job",
              queue_name=~"$queue_name"
            }[$__rate_interval]
          )
        )
      )
    |||,
    local taskSucceededIntervalQuery = std.strReplace(taskFailedIntervalQuery, 'failed', 'succeeded'),
    local taskSentIntervalQuery = std.strReplace(taskFailedIntervalQuery, 'failed', 'sent'),
    local taskReceivedIntervalQuery = std.strReplace(taskFailedIntervalQuery, 'failed', 'received'),
    local taskRetriedIntervalQuery = std.strReplace(taskFailedIntervalQuery, 'failed', 'retried'),
    local taskRevokedIntervalQuery = std.strReplace(taskFailedIntervalQuery, 'failed', 'revoked'),
    local taskRejectedIntervalQuery = std.strReplace(taskFailedIntervalQuery, 'failed', 'rejected'),

    local tasksCompletedTimeSeriesPanel =
      timeSeriesPanel.new(
        'Tasks Completed',
      ) +
      tsQueryOptions.withTargets(
        [
          prometheus.new(
            '$datasource',
            taskSucceededIntervalQuery,
          ) +
          prometheus.withLegendFormat(
            'Succeeded'
          ),
          prometheus.new(
            '$datasource',
            taskFailedIntervalQuery,
          ) +
          prometheus.withLegendFormat(
            'Failed'
          ),
          prometheus.new(
            '$datasource',
            taskSentIntervalQuery,
          ) +
          prometheus.withLegendFormat(
            'Sent'
          ),
          prometheus.new(
            '$datasource',
            taskReceivedIntervalQuery,
          ) +
          prometheus.withLegendFormat(
            'Received'
          ),
          prometheus.new(
            '$datasource',
            taskRetriedIntervalQuery,
          ) +
          prometheus.withLegendFormat(
            'Retried'
          ),
          prometheus.new(
            '$datasource',
            taskRevokedIntervalQuery,
          ) +
          prometheus.withLegendFormat(
            'Revoked'
          ),
          prometheus.new(
            '$datasource',
            taskRejectedIntervalQuery,
          ) +
          prometheus.withLegendFormat(
            'Rejected'
          ),
        ]
      ) +
      tsStandardOptions.withUnit('short') +
      tsOptions.tooltip.withMode('multi') +
      tsOptions.tooltip.withSort('desc') +
      tsLegend.withShowLegend(true) +
      tsLegend.withDisplayMode('table') +
      tsLegend.withPlacement('right') +
      tsLegend.withCalcs(['mean', 'max']) +
      tsLegend.withSortBy('Mean') +
      tsLegend.withSortDesc(true) +
      tsCustom.withSpanNulls(false),

    local tasksRuntimeP50Query = |||
      histogram_quantile(0.50,
        sum(
          irate(
            celery_task_runtime_bucket{
              job="$job",
              queue_name=~"$queue_name"
            }[$__rate_interval]
          ) > 0
        ) by (job, le)
      )
    |||,
    local tasksRuntimeP95Query = std.strReplace(tasksRuntimeP50Query, '0.50', '0.95'),
    local tasksRuntimeP99Query = std.strReplace(tasksRuntimeP50Query, '0.50', '0.99'),

    local tasksRuntimeTimeSeriesPanel =
      timeSeriesPanel.new(
        'Tasks Runtime',
      ) +
      tsQueryOptions.withTargets(
        [
          prometheus.new(
            '$datasource',
            tasksRuntimeP50Query,
          ) +
          prometheus.withLegendFormat(
            'P50'
          ),
          prometheus.new(
            '$datasource',
            tasksRuntimeP95Query,
          ) +
          prometheus.withLegendFormat(
            'P95'
          ),
          prometheus.new(
            '$datasource',
            tasksRuntimeP99Query,
          ) +
          prometheus.withLegendFormat(
            'P99'
          ),
        ]
      ) +
      tsStandardOptions.withUnit('s') +
      tsOptions.tooltip.withMode('multi') +
      tsOptions.tooltip.withSort('desc') +
      tsStandardOptions.withOverrides([
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
      ]) +
      tsLegend.withShowLegend(true) +
      tsLegend.withDisplayMode('table') +
      tsLegend.withPlacement('right') +
      tsLegend.withCalcs(['mean', 'max']) +
      tsLegend.withSortBy('Mean') +
      tsLegend.withSortDesc(true) +
      tsCustom.withSpanNulls(false),

    local summaryRow =
      row.new(
        title='Summary'
      ),

    local queuesRow =
      row.new(
        title='Queues'
      ),

    local tasksRow =
      row.new(
        title='Tasks'
      ),


    'celery-tasks-overview.json':
      dashboard.new(
        'Celery / Tasks / Overview',
      ) +
      dashboard.withDescription(
        'A dashboard that monitors Celery. It is created using the Celery-mixin for the the (Celery-exporter)[https://github.com/danihodovic/celery-exporter].'
      ) +
      dashboard.withUid($._config.celeryTasksOverviewUid) +
      dashboard.withTags($._config.tags) +
      dashboard.withTimezone('utc') +
      dashboard.withEditable(true) +
      dashboard.time.withFrom('now-2d') +
      dashboard.time.withTo('now') +
      dashboard.withVariables(variables) +
      dashboard.withLinks(
        [
          dashboard.link.dashboards.new('Celery Dashboards', $._config.tags) +
          dashboard.link.link.options.withTargetBlank(true),
        ]
      ) +
      dashboard.withPanels(
        [
          summaryRow +
          row.gridPos.withX(0) +
          row.gridPos.withY(0) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
        ] +
        grid.makeGrid(
          [celeryWorkersStatPanel, celeryWorkersActiveStatPanel, tasksReceivedByWorkers24hStatPanel, taskSuccessRate1wStatPanel],
          panelWidth=5,
          panelHeight=4,
          startY=1
        ) +
        [
          taskRuntime1wStatPanel +
          timeSeriesPanel.gridPos.withX(20) +
          timeSeriesPanel.gridPos.withY(1) +
          timeSeriesPanel.gridPos.withW(4) +
          timeSeriesPanel.gridPos.withH(4),
        ] +
        grid.makeGrid(
          [tasksFailed1wTable, taskExceptions1wTable, tasksRuntime1wTable],
          panelWidth=8,
          panelHeight=8,
          startY=5
        ) +
        [
          queuesRow +
          row.gridPos.withX(0) +
          row.gridPos.withY(13) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
          celeryQueueLengthTimeSeriesPanel +
          timeSeriesPanel.gridPos.withX(0) +
          timeSeriesPanel.gridPos.withY(14) +
          timeSeriesPanel.gridPos.withW(24) +
          timeSeriesPanel.gridPos.withH(6),
        ] +
        [
          tasksRow +
          row.gridPos.withX(0) +
          row.gridPos.withY(20) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
          tasksStatsTable +
          tablePanel.gridPos.withX(0) +
          tablePanel.gridPos.withY(21) +
          tablePanel.gridPos.withW(24) +
          tablePanel.gridPos.withH(4),
          tasksCompletedTimeSeriesPanel +
          timeSeriesPanel.gridPos.withX(0) +
          timeSeriesPanel.gridPos.withY(25) +
          timeSeriesPanel.gridPos.withW(24) +
          timeSeriesPanel.gridPos.withH(10),
          tasksRuntimeTimeSeriesPanel +
          timeSeriesPanel.gridPos.withX(0) +
          timeSeriesPanel.gridPos.withY(35) +
          timeSeriesPanel.gridPos.withW(24) +
          timeSeriesPanel.gridPos.withH(10),
        ]
      ) +
      if $._config.annotation.enabled then
        dashboard.withAnnotations($._config.customAnnotation)
      else {},
  },
}
