initNode() {
  systemctl unmask ssh
  systemctl enable ssh
  systemctl start ssh
  echo 'root:rabbitmq' | chpasswd
  echo 'ubuntu:rabbitmq' | chpasswd
}