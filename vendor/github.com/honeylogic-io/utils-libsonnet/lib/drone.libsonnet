local pythonStepCommon = {
  depends_on: ['install-python-deps'],
  commands: [
    '. .poetry/env && . $(poetry env info -p)/bin/activate',
  ],
};

local installDepsStep = pythonStepCommon {
  name: 'install-python-deps',
  depends_on: ['restore-cache'],
  environment: {
    POETRY_CACHE_DIR: '/drone/src/.poetry-cache',
    POETRY_VIRTUALENVS_IN_PROJECT: 'false',
  },
  commands: [
    |||
      export POETRY_HOME=$DRONE_WORKSPACE/.poetry
      if [ ! -d "$POETRY_HOME" ]; then
        curl -fsS -o /tmp/get-poetry.py https://raw.githubusercontent.com/python-poetry/poetry/master/get-poetry.py
        python /tmp/get-poetry.py -y
      fi
    |||,
    '. .poetry/env',
    'poetry install --no-root',
  ],
};

local formatStep = pythonStepCommon {
  name: 'format',
  commands+: [
    'black . --check',
    'isort --check-only .',
  ],
};

local mypyStep = pythonStepCommon {
  name: 'typecheck',
  commands+: [
    'mypy .',
  ],
};


local pylintStep = pythonStepCommon {
  name: 'lint',
  commands+: [
    "pylint $(git ls-files -- '*.py' ':!:**/migrations/*.py')",
  ],
};

local testStep = pythonStepCommon {
  name: 'test',
  commands+: ['pytest --ignore .poetry --ignore .poetry-cache --cov'],
};


local pipelineCommon(image) = {
  kind: 'pipeline',
  type: 'docker',
  name: 'python',
  trigger: {
    event: [
      'push',
    ],
  },
  volumes: [
    {
      name: 'cache',
      host: {
        path: '/tmp/cache',
      },
    },
  ],
  steps: [
    installDepsStep { image: image },
    formatStep { image: image },
    mypyStep { image: image },
    pylintStep { image: image },
    testStep { image: image },
  ],
};

{
  pythonPipeline: {
    new(pipeline, image): pipelineCommon(image) + pipeline,
  },
  dockerPipeline: {
    kind: 'pipeline',
    type: 'docker',
  },
}
