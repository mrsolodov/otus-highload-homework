job "otus-portal" {
  datacenters = ["dc1"]
  type = "service"
  group "web" {
    count = 2
    network {
      port "http" {
        to = 8080
      }
    }
    service {
      name = "otus-portal"
      provider = "nomad"
      port = "http"
      check {
        type = "http"
        path = "/health"
        interval = "10s"
        timeout = "2s"
      }
    }
    task "portal" {
      driver = "docker"
      user = "65532"
      config {
        image = "otus-portal:33"
        ports = ["http"]
        extra_hosts = ["host.docker.internal:host-gateway"]
      }
      env {
        DB_HOST = "host.docker.internal"
        DB_PORT = "5432"
        DB_NAME = "portal"
        PORT = "8080"
      }
      vault {
        role = "portal"
        env = false
        disable_file = true
      }
      template {
        data = <<-EOF
        {{ with secret "database/creds/portal" }}{"username": {{ .Data.username | toJSON }}, "password": {{ .Data.password | toJSON }}}{{ end }}
        EOF
        destination = "secrets/db.json"
        perms = "0600"
        uid = 65532
        gid = 65532
        change_mode = "noop"
      }
      resources {
        cpu = 100
        memory = 128
      }
    }
  }
}
