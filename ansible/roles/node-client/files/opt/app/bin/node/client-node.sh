initNode() {
  _initNode
  echo -e "client\nclient\n" | adduser client > /dev/nul 2>&1 || echo "client:client" | chpasswd
}