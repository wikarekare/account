# Uber class for common methods
class Graph_Parent
  def adsl_ip?(address)
    return address == EXTERNAL5 || address == EXTERNAL6 || address == EXTERNAL7
  end

  def ignore?(dest_address)
    dest_ip = dest_address.split('.')
    return ( adsl_ip?(dest_address) ||
             dest_ip[0] == '10' ||  # Destination is 10.0.0.0/8
             ( dest_ip[0] == '192' && dest_ip[1] == '168' ) || # Destination is 192.168.0.0/16
             ( dest_ip[0] == '100' && dest_ip[1] == '64' ) || # Destination is 100.64.0.0/16
             ( dest_ip[0] == '172' && dest_ip[1].to_i >= 16 && dest_ip[1].to_i < 32 ) || # Destination is 172.16.0.0/12
             dest_address == '255.255.255.255' || # Broadcast
             ( dest_ip[0] >= '224' && dest_ip[0] <= '239' )   # Destination is multicast
           )
  end
end
