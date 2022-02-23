local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local ingress = k.networking.v1.ingress;

local mapRules(host, service, servicePort) = ({ host: host, http: { paths: [{
                                                path: '/',
                                                pathType: 'Prefix',
                                                backend: { service: { name: service, port: { number: servicePort } } },
                                              }] } });

{
  new(name, hosts, service, servicePort, annotations):
    ingress.new(name)
    + ingress.metadata.withAnnotations(annotations)
    + ingress.spec.withTls([{ hosts: hosts, secretName: name + '-cert' }])
    + ingress.spec.withRules([mapRules(host, service, servicePort) for host in hosts]),
}
