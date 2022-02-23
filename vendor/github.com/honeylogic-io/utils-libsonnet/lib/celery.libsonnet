local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local statefulSet = k.apps.v1.statefulSet;
local container = k.core.v1.container;
local deployment = k.apps.v1.deployment;

{
  createContainers(name, image, command, args, env):: container.new(name, image) +
                                                      container.withCommand(command) +
                                                      container.withArgs(args) +
                                                      container.withEnvMap(env) +
                                                      container.withImagePullPolicy('Always'),

  worker: {
    new(name, image, replicas=1, command=['celery'], args, env): {
      local containers = $.createContainers(name, image, command, args, env),
      statefulSet: statefulSet.new(name, replicas, containers) +
                   statefulSet.spec.withServiceName(name),
    },
  },
  beat: {
    new(name, image, command=['celery'], args, env): {
      local containers = $.createContainers(name, image, command, args, env),
      deployment: deployment.new(name, replicas=1, containers=containers),
    },
  },
}
