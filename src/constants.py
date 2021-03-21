class LabelName:
    NAME = "name"
    HOSTNAME = "hostname"
    EXCEPTION = "exception"


TASK_EVENT_LABELS = [LabelName.NAME, LabelName.HOSTNAME]
WORKER_EVENT_LABELS = [LabelName.HOSTNAME]


class EventName:
    TASK_SENT = "task-sent"
    TASK_RECEIVED = "task-received"
    TASK_STARTED = "task-started"
    TASK_SUCCEEDED = "task-succeeded"
    TASK_FAILED = "task-failed"
    TASK_REJECTED = "task-rejected"
    TASK_REVOKED = "task-revoked"
    TASK_RETRIED = "task-retried"
    WORKER_HEARTBEAT = "worker-heartbeat"
    WORKER_ONLINE = "worker-online"
    WORKER_OFFLINE = "worker-offline"


class EventEnum:
    TYPE = 'type'
    HOSTNAME = 'hostname'
    UUID = 'uuid'
