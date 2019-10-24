initNode() {
  echo 'root:rabbitmq'   | chpasswd
  echo 'ubuntu:rabbitmq' | chpasswd
  ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -P ""
  ssh-keygen -t dsa -f /etc/ssh/ssh_host_ed25519_key -P ""
  systemctl unmask ssh
  systemctl enable ssh
  systemctl start ssh

}