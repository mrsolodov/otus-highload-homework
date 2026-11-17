nginx:
  pkg.installed: []

/etc/nginx/sites-available/default:
  file.managed:
    - source: salt://web/default.conf.j2
    - template: jinja
    - user: root
    - group: root
    - mode: '0644'
    - require:
      - pkg: nginx

/var/www/html/index.html:
  file.managed:
    - source: salt://web/index.html.j2
    - template: jinja
    - user: root
    - group: root
    - mode: '0644'
    - require:
      - pkg: nginx

nginx-service:
  service.running:
    - name: nginx
    - enable: true
    - require:
      - pkg: nginx
    - watch:
      - file: /etc/nginx/sites-available/default
