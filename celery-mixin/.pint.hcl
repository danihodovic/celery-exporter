rule {
  match {
    name = "CeleryTaskHighFailRate"
  }
  disable = ["promql/regexp"]
}

rule {
  match {
    name = "CeleryHighQueueLength"
  }
  disable = ["promql/regexp"]
}

rule {
  match {
    name = "CeleryWorkerDown"
  }
  disable = ["promql/regexp"]
}
