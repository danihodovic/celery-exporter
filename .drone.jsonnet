local drone = import 'vendor/github.com/honeylogic-io/utils-libsonnet/lib/drone.libsonnet';

local cacheStepCommon = {
  image: 'meltwater/drone-cache',
  environment: {
    AWS_ACCESS_KEY_ID: {
      from_secret: 'AWS_ACCESS_KEY_ID',
    },
    AWS_SECRET_ACCESS_KEY: {
      from_secret: 'AWS_SECRET_ACCESS_KEY',
    },
  },
  settings: {
    cache_key: '{{ .Repo.Name }}_{{ checksum "poetry.lock" }}',
    region: 'eu-central-1',
    bucket: 'depode-ci-cache',
    mount: [
      '.poetry',
      '.poetry-cache',
    ],
  },
  volumes: [{ name: 'cache', path: '/tmp/cache' }],
};

local rebuildCacheStep = cacheStepCommon {
  name: 'rebuild-cache',
  depends_on: [
    'install-python-deps',
  ],
  settings+: {
    rebuild: true,
  },
};

local restoreCacheStep = cacheStepCommon {
  name: 'restore-cache',
  settings+: {
    restore: true,
  },
};


local pythonPipelineWithoutCache = drone.pythonPipeline.new({
  environment: {
    POETRY_CACHE_DIR: '/drone/src/.poetry-cache',
    POETRY_VIRTUALENVS_IN_PROJECT: 'true',
  },
}, 'python:3.9');

local pythonPipeline = pythonPipelineWithoutCache {
  steps: [restoreCacheStep] + pythonPipelineWithoutCache.steps + [rebuildCacheStep],
};

[
  pythonPipeline,
]
