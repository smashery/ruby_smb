#!/usr/bin/ruby

require 'bundler/setup'
require 'ruby_smb'

# 192.168.172.138

def run_negotiation(address, smb1, smb2)
  # Create our socket and add it to the dispatcher
  sock = TCPSocket.new address, 445
  dispatcher = RubySMB::Dispatcher::Socket.new(sock)

  client = RubySMB::Client.new(dispatcher, smb1: smb1, smb2: smb2)
  client.negotiate
end

# Negotiate with both SMB1 and SMB2 enabled on the client
run_negotiation(ARGV[0], true, true)
# Negotiate with only SMB1 enabled
run_negotiation(ARGV[0], true, false)
# Negotiate with only SMB2 enabled
run_negotiation(ARGV[0], false, true)
