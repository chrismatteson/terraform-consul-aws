#!/bin/bash 

function has_yum {
  [ -n "$(command -v yum)" ]
}

function has_apt_get {
  [ -n "$(command -v apt-get)" ]
}

log_info "Installing dependencies"

if $(has_apt_get); then
  sudo apt-get update -y
  sudo apt-get install -y awscli curl unzip jq
elif $(has_yum); then
  sudo yum update -y
  sudo yum install -y aws curl unzip jq
else
  log_error "Could not find apt-get or yum. Cannot install dependencies on this OS."
  exit 1
fi


curl -O https://raw.githubusercontent.com/hashicorp/terraform-aws-consul/master/modules/install-consul/install-consul -O https://raw.githubusercontent.com/hashicorp/terraform-aws-consul/master/modules/run-consul/run-consul

chmod +x ./install-consul
chmod +x ./run-consul
/bin/bash ./install-consul %{ if version != "" }--version ${version} %{ endif}%{ if download-url != "" }--download-url ${download-url} %{ endif}%{ if path != "" }--path ${path} %{ endif}%{ if user != "" }--user ${user} %{ endif}%{ if ca-file-path != "" }--ca-file-path ${download-url} %{ endif}%{ if cert-file-path != "" }--cert-file-path ${cert-file-path} %{ endif}%{ if key-file-path != "" }--key-file-path ${key-file-path} %{ endif}
cp ./run-consul /opt/consul/bin/run-consul
/bin/bash /opt/consul/bin/run-consul %{ if server == true }--server %{ endif}%{ if client == true }--client %{ endif}%{ if config-dir != "" }--config-dir ${config-dir} %{ endif}%{ if data-dir != "" }--data-dir ${data-dir} %{ endif}%{ if systemd-stdout != "" }--systemd-stdout ${systemd-stdout} %{ endif}%{ if systemd-stderr != "" }--systemd-stderr ${systemd-stderr} %{ endif}%{ if bin-dir != "" }--bin-dir ${bin-dir} %{ endif}%{ if user != "" }--user ${user} %{ endif}%{ if cluster-tag-key != "" }--cluster-tag-key ${cluster-tag-key} %{ endif}%{ if cluster-tag-value != "" }--cluster-tag-value ${cluster-tag-value} %{ endif}%{ if datacenter != "" }--datacenter ${datacenter} %{ endif}%{ if autopilot-cleanup-dead-servers != "" }--autopilot-cleanup-dead-servers ${autopilot-cleanup-dead-servers} %{ endif}%{ if autopilot-last-contact-threshold != "" }--autopilot-last-contact-threshold ${autopilot-last-contact-threshold} %{ endif}%{ if autopilot-max-trailing-logs != "" }--autopilot-max-trailing-logs ${autopilot-max-trailing-logs} %{ endif}%{ if autopilot-server-stabilization-time != "" }--autopilot-server-stabilization-time ${autopilot-server-stabilization-time} %{ endif}%{ if autopilot-redundancy-zone-tag != "" }--autopilot-redundancy-zone-tag ${autopilot-redundancy-zone-tag} %{ endif}%{ if autopilot-disable-upgrade-migration != "" }--autopilot-disable-upgrade-migration ${autopilot-disable-upgrade-migration} %{ endif}%{ if autopilot-upgrade-version-tag != "" }--autopilot-upgrade-version-tag ${autopilot-upgrade-version-tag} %{ endif}%{ if enable-gossip-encryption != "" }--enable-gossip-encryption ${enable-gossip-encryption} %{ endif}%{ if gossip-encryption-key != "" }--gossip-encryption-key ${gossip-encryption-key} %{ endif}%{ if enable-rpc-encryption != "" }--enable-rpc-encryption ${enable-rpc-encryption} %{ endif}%{ if ca-file-path != "" }--ca-path ${ca-file-path} %{ endif}%{ if cert-file-path != "" }--cert-file-path ${cert-file-path} %{ endif}%{ if key-file-path != "" }--key-file-path ${key-file-path} %{ endif}%{ if environment != "" }--environment ${environment} %{ endif}%{ if skip-consul-config != "" }--skip-consul-config ${skip-consul-config} %{ endif}%{ if recursor != "" }--recursor ${recursor} %{ endif}
