local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';

local dashboard = g.dashboard;
local row = g.panel.row;
local grid = g.util.grid;

local variable = dashboard.variable;
local datasource = variable.datasource;
local query = variable.query;
local prometheus = g.query.prometheus;

local timeSeriesPanel = g.panel.timeSeries;
local tablePanel = g.panel.table;

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

    local taskVariable =
      query.new(
        'task',
        'label_values(celery_task_received_total{namespace="$namespace", job="$job", queue_name=~"$queue_name", name!~"%(celeryIgnoredTasks)s"}, name)' % $._config
      ) +
      query.withDatasourceFromVariable(datasourceVariable) +
      query.withSort(1) +
      query.generalOptions.withLabel('Task') +
      query.selectionOptions.withMulti(true) +
      query.selectionOptions.withIncludeAll(false) +
      query.refresh.onLoad() +
      query.refresh.onTime(),

    local variables = [
      datasourceVariable,
      namespaceVariable,
      jobVariable,
      queueNameVariable,
      taskVariable,
    ],

    local taskExceptionsQuery = |||
      round(
        sum (
          increase(
            celery_task_failed_total{
              job="$job",
              name=~"$task",
              queue_name=~"$queue_name"
            }[$__range]
          )
        ) by (name, exception) > 0
      )
    |||,
    local taskExceptionsTable =
      tablePanel.new(
        'Task Exceptions',
      ) +
      tbStandardOptions.withUnit('short') +
      tbOptions.withSortBy(
        tbOptions.sortBy.withDisplayName('Value') +
        tbOptions.sortBy.withDesc(true)
      ) +
      tbOptions.footer.TableFooterOptions.withEnablePagination(true) +
      tbQueryOptions.withTargets(
        prometheus.new(
          '$datasource',
          taskExceptionsQuery,
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
      ]),

    local taskFailedQuery = |||
      sum (
        round(
          increase(
            celery_task_failed_total{
              job="$job",
              name=~"$task",
              queue_name=~"$queue_name"
            }[$__range]
          )
        )
      ) by (name) > 0
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
        tbOptions.sortBy.withDisplayName('Success Rate') +
        tbOptions.sortBy.withDesc(true)
      ) +
      tbOptions.footer.TableFooterOptions.withEnablePagination(true) +
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
      ]) +
      tbStandardOptions.withOverrides([
        tbOverride.byName.new('Success Rate') +
        tbOverride.byName.withPropertiesFromOptions(
          tbStandardOptions.withUnit('percentunit')
        ),
      ]),

    local taskFailedByExceptionIntervalQuery = |||
      sum (
        round(
          increase(
            celery_task_failed_total{
              job="$job",
              name=~"$task",
              queue_name=~"$queue_name"
            }[$__rate_interval]
          )
        )
      ) by (name, exception)
    |||,

    local tasksFailedByExceptionTimeSeriesPanel =
      timeSeriesPanel.new(
        'Task Exceptions',
      ) +
      tsQueryOptions.withTargets(
        [
          prometheus.new(
            '$datasource',
            taskFailedByExceptionIntervalQuery,
          ) +
          prometheus.withLegendFormat(
            '{{ name }}/{{ exception }}'
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

    local taskFailedIntervalQuery = |||
      sum (
        round(
          increase(
            celery_task_failed_total{
              job="$job",
              name=~"$task",
              queue_name=~"$queue_name"
            }[$__rate_interval]
          )
        )
      ) by (name)
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
            'Succeeded - {{ name }}'
          ),
          prometheus.new(
            '$datasource',
            taskFailedIntervalQuery,
          ) +
          prometheus.withLegendFormat(
            'Failed - {{ name }}'
          ),
          prometheus.new(
            '$datasource',
            taskSentIntervalQuery,
          ) +
          prometheus.withLegendFormat(
            'Sent - {{ name }}'
          ),
          prometheus.new(
            '$datasource',
            taskReceivedIntervalQuery,
          ) +
          prometheus.withLegendFormat(
            'Received - {{ name }}'
          ),
          prometheus.new(
            '$datasource',
            taskRetriedIntervalQuery,
          ) +
          prometheus.withLegendFormat(
            'Retried - {{ name }}'
          ),
          prometheus.new(
            '$datasource',
            taskRevokedIntervalQuery,
          ) +
          prometheus.withLegendFormat(
            'Revoked - {{ name }}'
          ),
          prometheus.new(
            '$datasource',
            taskRejectedIntervalQuery,
          ) +
          prometheus.withLegendFormat(
            'Rejected - {{ name }}'
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
              name=~"$task",
              queue_name=~"$queue_name"
            }[$__rate_interval]
          ) > 0
        ) by (name, job, le)
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
            'P50 - {{ name }}'
          ),
          prometheus.new(
            '$datasource',
            tasksRuntimeP95Query,
          ) +
          prometheus.withLegendFormat(
            'P95 - {{ name }}'
          ),
          prometheus.new(
            '$datasource',
            tasksRuntimeP99Query,
          ) +
          prometheus.withLegendFormat(
            'P99 - {{ name }}'
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

    local tasksRow =
      row.new(
        title='Tasks'
      ),


    'celery-tasks-by-task.json':
      dashboard.new(
        'Celery / Tasks / By Task',
      ) +
      dashboard.withDescription(
        'A dashboard that monitors Celery. It is created using the Celery-mixin for the the (Celery-exporter)[https://github.com/danihodovic/celery-exporter]'
      ) +
      dashboard.withUid($._config.celeryTasksByTaskUid) +
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
          tasksRow +
          row.gridPos.withX(0) +
          row.gridPos.withY(0) +
          row.gridPos.withW(24) +
          row.gridPos.withH(1),
          tasksStatsTable +
          timeSeriesPanel.gridPos.withX(0) +
          timeSeriesPanel.gridPos.withY(1) +
          timeSeriesPanel.gridPos.withW(16) +
          timeSeriesPanel.gridPos.withH(8),
          taskExceptionsTable +
          timeSeriesPanel.gridPos.withX(16) +
          timeSeriesPanel.gridPos.withY(1) +
          timeSeriesPanel.gridPos.withW(8) +
          timeSeriesPanel.gridPos.withH(8),
          tasksCompletedTimeSeriesPanel +
          timeSeriesPanel.gridPos.withX(0) +
          timeSeriesPanel.gridPos.withY(9) +
          timeSeriesPanel.gridPos.withW(24) +
          timeSeriesPanel.gridPos.withH(8),
          tasksFailedByExceptionTimeSeriesPanel +
          timeSeriesPanel.gridPos.withX(0) +
          timeSeriesPanel.gridPos.withY(17) +
          timeSeriesPanel.gridPos.withW(24) +
          timeSeriesPanel.gridPos.withH(8),
          tasksRuntimeTimeSeriesPanel +
          timeSeriesPanel.gridPos.withX(0) +
          timeSeriesPanel.gridPos.withY(25) +
          timeSeriesPanel.gridPos.withW(24) +
          timeSeriesPanel.gridPos.withH(8),
        ]
      ) +
      if $._config.annotation.enabled then
        dashboard.withAnnotations($._config.customAnnotation)
      else {},
  },
}
