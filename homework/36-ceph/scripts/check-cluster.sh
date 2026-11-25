#!/usr/bin/env bash
set -euo pipefail

ceph -s
ceph orch host ls
ceph orch ps --daemon-type mon
ceph orch ps --daemon-type mgr
ceph orch ps --daemon-type osd
ceph orch ps --daemon-type mds
ceph osd tree
ceph osd pool ls detail
ceph fs status cephfs
ceph health detail
