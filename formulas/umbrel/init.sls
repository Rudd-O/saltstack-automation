/etc/systemd/system/umbrel.service:
  file.managed:
  - contents: |
      [Unit]
      Description=Umbrel service collection
      After=network-online.target
      
      [Service]
      Type=oneshot
      RemainAfterExit=true
      ExecStart=/opt/umbrel/scripts/start
      ExecStop=/opt/umbrel/scripts/stop
      
      [Install]
      WantedBy=multi-user.target
  - user: root
  - group: root
  - mode: 0644
  - watch_in:
    - cmd: reload systemd

Mask qubes iptables:
  cmd.run:
  - name: |
      set -e
      if grep -q ExecStart /etc/systemd/system/qubes-iptables.service.d/mask.conf
      then
          exit
      fi
      mkdir -p /etc/systemd/system/qubes-iptables.service.d/
      echo "[Service]
      ExecStart=
      ExecStart=/usr/bin/echo Disabled
      " > /etc/systemd/system/qubes-iptables.service.d/mask.conf
      echo
      echo changed=yes
  - stateful: yes

reload systemd:
  cmd.wait:
  - name: systemctl --system daemon-reload

umbrel:
  service.running:
  - enable: true
  - watch:
    - file: /etc/systemd/system/umbrel.service
  - require:
    - cmd: reload systemd

umbrel-status:
  cmd.run:
  - name: systemctl --system status umbrel.service >&2
  - stateful: yes
  - require:
    - service: umbrel
