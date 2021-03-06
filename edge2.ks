lang en_US.UTF-8
keyboard us
timezone UTC
zerombr
clearpart --all --initlabel
autopart --type=plain --fstype=xfs --nohome
reboot
text
network --bootproto=dhcp
user --name=core --groups=wheel --password=edge

ostreesetup --nogpg --url=http://10.0.2.2:8000/repo/ --osname=rhel --remote=edge --ref=rhel/8/x86_64/edge
%post

#stage updates as they become available. This is highly recommended
echo AutomaticUpdatePolicy=stage >> /etc/rpm-ostreed.conf

#This is a simple example that will look for staged rpm-ostree updates and apply them per the timer if they exist
cat > /etc/systemd/system/applyupdate.service << 'EOF'
[Unit]
Description=Apply Update Check

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'if [[ $(rpm-ostree status -v | grep "Staged: yes") ]]; then systemctl --message="Applying OTA update" reboot; else logger "Running latest available update"; fi'
EOF

cat > /etc/systemd/system/applyupdate.timer << EOF
[Unit]
Description=Daily Update Reboot Check.

[Timer]
#Nightly example maintenance window
OnCalendar=*-*-* 01:30:00
#weekly example for Sunday at midnight
#OnCalendar=Sun *-*-* 00:00:00

[Install]
WantedBy=multi-user.target
EOF

systemctl enable rpm-ostreed-automatic.timer applyupdate.timer
%end

%post
#Add a podman autoupdate timer & service

cat > /etc/systemd/system/podman-auto-update.service << EOF
[Unit]
Description=Podman auto-update service
Documentation=man:podman-auto-update(1)
Wants=network.target
After=network-online.target

[Service]
ExecStart=/usr/bin/podman auto-update

[Install]
WantedBy=multi-user.target default.target
EOF

cat > /etc/systemd/system/podman-auto-update.timer << EOF
[Unit]
Description=Podman auto-update timer

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=7200

[Install]
WantedBy=timers.target
EOF

#create a unit file to run our example workload 
cat > /etc/systemd/system/container-boinc.service <<EOF
# container-boinc.service
# autogenerated by Podman 2.0.4

[Unit]
Description=Podman container-boinc.service
Documentation=man:podman-generate-systemd(1)
Wants=network.target
After=network-online.target

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=on-failure
RestartSec=30s
ExecStartPre=/bin/rm -f %t/container-boinc.pid %t/container-boinc.ctr-id
ExecStart=/usr/bin/podman run --conmon-pidfile %t/container-boinc.pid --cidfile %t/container-boinc.ctr-id --cgroups=no-conmon -d --replace --label io.containers.autoupdate=image --name boinc -dt -p 31416:31416 -v /opt/appdata/boinc:/var/lib/boinc:Z boinc/client:latest
ExecStop=/usr/bin/podman stop --ignore --cidfile %t/container-boinc.ctr-id -t 10
ExecStopPost=/usr/bin/podman rm --ignore -f --cidfile %t/container-boinc.ctr-id
PIDFile=%t/container-boinc.pid
KillMode=none
Type=forking

[Install]
WantedBy=multi-user.target default.target
EOF


#Example workload from: https://fedoramagazine.org/running-rosettahome-on-a-raspberry-pi-with-fedora-iot/
#create host mount points
mkdir -p /opt/appdata/boinc/slots /opt/appdata/boinc/locale

systemctl enable podman-auto-update.timer container-boinc.service
%end
