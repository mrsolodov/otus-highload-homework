iptables-package:
  pkg.installed:
    - name: iptables

iptables-persistent-package:
  pkg.installed:
    - name: iptables-persistent

allow-loopback:
  iptables.append:
    - table: filter
    - chain: INPUT
    - in-interface: lo
    - jump: ACCEPT
    - save: true
    - require:
      - pkg: iptables-package
      - pkg: iptables-persistent-package

allow-established:
  iptables.append:
    - table: filter
    - chain: INPUT
    - match: conntrack
    - ctstate: ESTABLISHED,RELATED
    - jump: ACCEPT
    - save: true
    - require:
      - iptables: allow-loopback

allow-ssh:
  iptables.append:
    - table: filter
    - chain: INPUT
    - protocol: tcp
    - dport: 22
    - jump: ACCEPT
    - save: true
    - require:
      - iptables: allow-established

allow-http:
  iptables.append:
    - table: filter
    - chain: INPUT
    - protocol: tcp
    - dport: 80
    - jump: ACCEPT
    - save: true
    - require:
      - iptables: allow-ssh

allow-icmp:
  iptables.append:
    - table: filter
    - chain: INPUT
    - protocol: icmp
    - jump: ACCEPT
    - save: true
    - require:
      - iptables: allow-http

{% if grains['id'] == 'web1' %}
allow-salt-master:
  iptables.append:
    - table: filter
    - chain: INPUT
    - protocol: tcp
    - dports:
      - 4505
      - 4506
    - jump: ACCEPT
    - save: true
    - require:
      - iptables: allow-icmp

drop-other-inbound:
  iptables.set_policy:
    - table: filter
    - chain: INPUT
    - policy: DROP
    - save: true
    - require:
      - iptables: allow-salt-master
{% else %}
drop-other-inbound:
  iptables.set_policy:
    - table: filter
    - chain: INPUT
    - policy: DROP
    - save: true
    - require:
      - iptables: allow-icmp
{% endif %}
