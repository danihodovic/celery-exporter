from prometheus_client import Counter, Gauge


class EventInstrumentMixin:
    @property
    def labelnames(self):
        return self._labelnames

    @property
    def name(self):
        return self._name


class EventCounter(Counter, EventInstrumentMixin):
    pass


class EventGauge(Gauge, EventInstrumentMixin):
    pass
