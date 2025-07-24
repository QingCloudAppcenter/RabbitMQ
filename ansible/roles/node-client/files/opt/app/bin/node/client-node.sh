initNode() {
  _initNode
  echo 'root:rabbitmq123' | chpasswd
  echo -e "client\nclient\n" | adduser client > /dev/nul 2>&1 || echo "client:client123" | chpasswd
}