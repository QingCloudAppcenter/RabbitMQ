initNode() {
  _initNode
  echo 'root:rabbitmq123' | chpasswd
  echo -e "client\nclient\n" | adduser client > /dev/null 2>&1 && echo "client:rabbitmq123" | chpasswd
}