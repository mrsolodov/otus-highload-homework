datacenter = "dc1"
data_dir = "/opt/nomad/data"
bind_addr = "0.0.0.0"
server {
  enabled = true
  bootstrap_expect = 1
}
client {
  enabled = true
}
vault {
  enabled = true
  address = "http://127.0.0.1:8200"
  default_identity {
    aud = ["vault.io"]
    ttl = "1h"
  }
}
