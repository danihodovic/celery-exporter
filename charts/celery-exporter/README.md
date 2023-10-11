# celery-exporter

![Version: 0.7.0](https://img.shields.io/badge/Version-0.7.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.9.2](https://img.shields.io/badge/AppVersion-0.9.2-informational?style=flat-square)

Prometheus exporter for Celery

**Homepage:** <https://github.com/danihodovic/celery-exporter>

## Maintainers

| Name        | Email | Url |
| ----------- | ----- | --- |
| danihodovic |       |     |
| adinhodovic |       |     |

## Source Code

- <https://github.com/danihodovic/celery-exporter>

## Values

| Key                                | Type   | Default                         | Description |
| ---------------------------------- | ------ | ------------------------------- | ----------- |
| affinity                           | object | `{}`                            |             |
| fullnameOverride                   | string | `""`                            |             |
| image.pullPolicy                   | string | `"IfNotPresent"`                |             |
| image.repository                   | string | `"danihodovic/celery-exporter"` |             |
| image.tag                          | string | `""`                            |             |
| imagePullSecrets                   | list   | `[]`                            |             |
| ingress.annotations                | object | `{}`                            |             |
| ingress.className                  | string | `""`                            |             |
| ingress.enabled                    | bool   | `false`                         |             |
| ingress.hosts[0].host              | string | `"celery-exporter.example"`     |             |
| ingress.hosts[0].paths[0].path     | string | `"/"`                           |             |
| ingress.hosts[0].paths[0].pathType | string | `"ImplementationSpecific"`      |             |
| ingress.tls                        | list   | `[]`                            |             |
| nameOverride                       | string | `""`                            |             |
| nodeSelector                       | object | `{}`                            |             |
| podAnnotations                     | object | `{}`                            |             |
| podSecurityContext                 | object | `{}`                            |             |
| replicaCount                       | int    | `1`                             |             |
| resources                          | object | `{}`                            |             |
| securityContext                    | object | `{}`                            |             |
| service.port                       | int    | `9808`                          |             |
| service.type                       | string | `"ClusterIP"`                   |             |
| serviceAccount.annotations         | object | `{}`                            |             |
| serviceAccount.create              | bool   | `true`                          |             |
| serviceAccount.name                | string | `""`                            |             |
| serviceMonitor.additionalLabels    | object | `{}`                            |             |
| serviceMonitor.enabled             | bool   | `false`                         |             |
| serviceMonitor.metricRelabelings   | list   | `[]`                            |             |
| serviceMonitor.namespace           | string | `""`                            |             |
| serviceMonitor.namespaceSelector   | object | `{}`                            |             |
| serviceMonitor.relabelings         | list   | `[]`                            |             |
| serviceMonitor.scrapeInterval      | string | `"30s"`                         |             |
| serviceMonitor.targetLabels        | list   | `[]`                            |             |
| tolerations                        | list   | `[]`                            |             |
| livenessProbe.timeoutSeconds       | object | `5`                             |             |
| livenessProbe.failureThreshold     | object | `5`                             |             |
| livenessProbe.periodSeconds        | object | `10`                            |             |
| livenessProbe.successThreshold     | object | `1`                             |             |
| readinessProbe.timeoutSeconds      | object | `5`                             |             |
| readinessProbe.failureThreshold    | object | `5`                             |             |
| readinessProbe.periodSeconds       | object | `10`                            |             |
| readinessProbe.namespaceSelector   | object | `1`                             |             |
